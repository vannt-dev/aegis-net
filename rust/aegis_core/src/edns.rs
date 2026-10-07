//! EDNS(0) padding for queries sent over an encrypted transport (RFC 7830).
//!
//! TLS hides what a query asks, not how long it is, and the length of a query
//! is mostly the length of the name. Padding every query up to the next
//! multiple of 128 octets, the block size RFC 8467 recommends for clients,
//! leaves an observer with a handful of sizes instead of one per name.

const HEADER_LEN: usize = 12;
const TYPE_OPT: u16 = 41;
const OPTION_PADDING: u16 = 12;
/// RFC 8467, section 4.1: clients pad queries to a multiple of 128 octets.
pub const QUERY_BLOCK: usize = 128;
/// The UDP payload size announced in an OPT record this module adds. 1232 is
/// the size the DNS flag day settled on; over TLS it is never tested.
const ADVERTISED_PAYLOAD: u16 = 1232;
/// Root name, TYPE, CLASS (payload size), TTL (extended RCODE and flags), RDLEN.
const OPT_FIXED_LEN: usize = 11;

/// A query ready to send, and whether the OPT record in it is ours.
#[derive(Debug, PartialEq, Eq)]
pub struct PaddedQuery {
    pub message: Vec<u8>,
    /// True when the client's query had no OPT record and one was added to
    /// carry the padding. The resolver then answers with an OPT record the
    /// client never asked for, which `strip_added_opt` takes back out.
    pub added_opt: bool,
}

fn read_u16(message: &[u8], at: usize) -> Option<u16> {
    Some(u16::from_be_bytes([
        *message.get(at)?,
        *message.get(at + 1)?,
    ]))
}

/// The offset just past the name that starts at `at`.
fn skip_name(message: &[u8], mut at: usize) -> Option<usize> {
    loop {
        let length = *message.get(at)?;
        match length & 0xc0 {
            // A compression pointer is two octets and ends the name.
            0xc0 => return Some(at + 2).filter(|end| *end <= message.len()),
            0x00 if length == 0 => return Some(at + 1),
            0x00 => at += 1 + usize::from(length),
            _ => return None,
        }
    }
}

/// Where the last record of the additional section starts and its type, when
/// the message has one. `None` for a message that does not parse.
fn last_additional(message: &[u8]) -> Option<Option<(usize, u16)>> {
    if message.len() < HEADER_LEN {
        return None;
    }
    let questions = read_u16(message, 4)?;
    let records = usize::from(read_u16(message, 6)?)
        + usize::from(read_u16(message, 8)?)
        + usize::from(read_u16(message, 10)?);
    let additional = usize::from(read_u16(message, 10)?);

    let mut at = HEADER_LEN;
    for _ in 0..questions {
        at = skip_name(message, at)? + 4;
    }
    let mut last = None;
    for index in 0..records {
        let start = at;
        let fixed = skip_name(message, at)?;
        let record_type = read_u16(message, fixed)?;
        let rdata_len = usize::from(read_u16(message, fixed + 8)?);
        at = fixed + 10 + rdata_len;
        if index + 1 == records && additional > 0 {
            last = Some((start, record_type));
        }
    }
    // Anything after the last record means the counts and the bytes disagree.
    (at == message.len()).then_some(last)
}

/// Whether the OPT RDATA already carries a padding option.
fn has_padding_option(rdata: &[u8]) -> bool {
    let mut at = 0;
    while at + 4 <= rdata.len() {
        let code = u16::from_be_bytes([rdata[at], rdata[at + 1]]);
        let length = usize::from(u16::from_be_bytes([rdata[at + 2], rdata[at + 3]]));
        if code == OPTION_PADDING {
            return true;
        }
        at += 4 + length;
    }
    false
}

/// How many padding octets bring a message of `length`, option header
/// included, up to the next block boundary.
fn padding_for(length: usize) -> usize {
    (QUERY_BLOCK - length % QUERY_BLOCK) % QUERY_BLOCK
}

/// Pad `query` to a multiple of `QUERY_BLOCK` octets.
///
/// The padding option goes into the query's own OPT record when it has one
/// as its last record, or into a new OPT record when it has none. A query
/// that does not parse, already carries padding, has its OPT record somewhere
/// other than last, or would grow past what a length prefix can express, is
/// sent as it is: padding is a courtesy to the user's privacy and must never
/// be the reason a lookup fails.
pub fn pad_query(query: &[u8]) -> PaddedQuery {
    let unpadded = || PaddedQuery {
        message: query.to_vec(),
        added_opt: false,
    };
    let Some(last) = last_additional(query) else {
        return unpadded();
    };

    let mut message = query.to_vec();
    let added_opt = match last {
        Some((start, TYPE_OPT)) => {
            let Some(fixed) = skip_name(query, start) else {
                return unpadded();
            };
            if has_padding_option(&query[fixed + 10..]) {
                return unpadded();
            }
            false
        }
        // An OPT record that is not last cannot be extended without moving
        // the records behind it.
        Some(_) if contains_opt(query) => return unpadded(),
        _ => {
            let Some(additional) = read_u16(query, 10).and_then(|count| count.checked_add(1))
            else {
                return unpadded();
            };
            message[10..12].copy_from_slice(&additional.to_be_bytes());
            message.push(0); // root name
            message.extend_from_slice(&TYPE_OPT.to_be_bytes());
            message.extend_from_slice(&ADVERTISED_PAYLOAD.to_be_bytes());
            message.extend_from_slice(&[0, 0, 0, 0]); // extended RCODE, version, flags
            message.extend_from_slice(&[0, 0]); // RDLEN, filled in below
            true
        }
    };

    let padding = padding_for(message.len() + 4);
    let total = message.len() + 4 + padding;
    if total > usize::from(u16::MAX) {
        return unpadded();
    }
    // The OPT record is last, so its RDLEN is the two octets before its RDATA
    // and its RDATA runs to the end of the message.
    let opt_start = match last {
        Some((start, TYPE_OPT)) => start,
        _ => message.len() - OPT_FIXED_LEN,
    };
    let Some(rdlen_at) = skip_name(&message, opt_start).map(|fixed| fixed + 8) else {
        return unpadded();
    };
    let Some(rdlen) = read_u16(&message, rdlen_at)
        .and_then(|length| usize::from(length).checked_add(4 + padding))
        .and_then(|length| u16::try_from(length).ok())
    else {
        return unpadded();
    };
    message[rdlen_at..rdlen_at + 2].copy_from_slice(&rdlen.to_be_bytes());
    message.extend_from_slice(&OPTION_PADDING.to_be_bytes());
    message.extend_from_slice(&(padding as u16).to_be_bytes());
    message.resize(total, 0);

    PaddedQuery { message, added_opt }
}

/// Whether any record of the message is an OPT record.
fn contains_opt(message: &[u8]) -> bool {
    let Some(questions) = read_u16(message, 4) else {
        return false;
    };
    let records = [6, 8, 10]
        .iter()
        .filter_map(|at| read_u16(message, *at))
        .map(usize::from)
        .sum::<usize>();
    let mut at = HEADER_LEN;
    for _ in 0..questions {
        match skip_name(message, at) {
            Some(end) => at = end + 4,
            None => return false,
        }
    }
    for _ in 0..records {
        let Some(fixed) = skip_name(message, at) else {
            return false;
        };
        let (Some(record_type), Some(rdata_len)) =
            (read_u16(message, fixed), read_u16(message, fixed + 8))
        else {
            return false;
        };
        if record_type == TYPE_OPT {
            return true;
        }
        at = fixed + 10 + usize::from(rdata_len);
    }
    false
}

/// Remove the OPT record from an answer to a query whose OPT record was added
/// by `pad_query`, so the client gets an answer shaped like its question.
///
/// Only an OPT record that is the last record is removed; anywhere else,
/// taking it out would shift the records behind it under their compression
/// pointers, and the answer is returned as it came.
pub fn strip_added_opt(answer: Vec<u8>) -> Vec<u8> {
    let Some(Some((start, TYPE_OPT))) = last_additional(&answer) else {
        return answer;
    };
    let Some(additional) = read_u16(&answer, 10).and_then(|count| count.checked_sub(1)) else {
        return answer;
    };
    let mut stripped = answer;
    stripped.truncate(start);
    stripped[10..12].copy_from_slice(&additional.to_be_bytes());
    stripped
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A query for `name`, type A, with no additional records.
    fn query(name: &str) -> Vec<u8> {
        let mut message = vec![0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0];
        for label in name.split('.') {
            message.push(label.len() as u8);
            message.extend_from_slice(label.as_bytes());
        }
        message.extend_from_slice(&[0, 0, 1, 0, 1]);
        message
    }

    /// Appends an OPT record carrying `options` as its RDATA.
    fn with_opt(mut message: Vec<u8>, options: &[u8]) -> Vec<u8> {
        let additional = read_u16(&message, 10).unwrap() + 1;
        message[10..12].copy_from_slice(&additional.to_be_bytes());
        message.push(0);
        message.extend_from_slice(&TYPE_OPT.to_be_bytes());
        message.extend_from_slice(&4096u16.to_be_bytes());
        message.extend_from_slice(&[0, 0, 0x80, 0]); // DO bit
        message.extend_from_slice(&(options.len() as u16).to_be_bytes());
        message.extend_from_slice(options);
        message
    }

    #[test]
    fn a_query_without_edns_gets_an_opt_record_and_fills_a_block() {
        let original = query("example.com");
        let padded = pad_query(&original);

        assert!(padded.added_opt);
        assert_eq!(padded.message.len(), QUERY_BLOCK);
        assert_eq!(
            padded.message[..10],
            original[..10],
            "header and counts before ARCOUNT"
        );
        assert_eq!(read_u16(&padded.message, 10), Some(1));
        assert_eq!(padded.message[12..original.len()], original[12..]);

        let opt = &padded.message[original.len()..];
        assert_eq!(opt[0], 0, "root name");
        assert_eq!(u16::from_be_bytes([opt[1], opt[2]]), TYPE_OPT);
        assert_eq!(u16::from_be_bytes([opt[3], opt[4]]), 1232);
        let rdlen = usize::from(u16::from_be_bytes([opt[9], opt[10]]));
        assert_eq!(rdlen, opt.len() - OPT_FIXED_LEN);
        assert_eq!(u16::from_be_bytes([opt[11], opt[12]]), OPTION_PADDING);
        let padding = usize::from(u16::from_be_bytes([opt[13], opt[14]]));
        assert_eq!(padding, rdlen - 4);
        assert!(
            opt[15..].iter().all(|octet| *octet == 0),
            "padding is zeros"
        );
        // The padded message is still one that parses to its last octet.
        assert_eq!(
            last_additional(&padded.message),
            Some(Some((original.len(), TYPE_OPT)))
        );
    }

    #[test]
    fn names_of_different_lengths_leave_the_same_size_on_the_wire() {
        let sizes: Vec<usize> = [
            "a.io",
            "example.com",
            "a-rather-long-host-name.internal.example.org",
        ]
        .iter()
        .map(|name| pad_query(&query(name)).message.len())
        .collect();
        assert_eq!(sizes, vec![QUERY_BLOCK; 3]);

        // A name long enough to spill over takes the next block, not a size of its own.
        let long = format!("{}.{}.example.com", "a".repeat(60), "b".repeat(60));
        assert_eq!(pad_query(&query(&long)).message.len(), 2 * QUERY_BLOCK);
    }

    #[test]
    fn a_query_with_edns_keeps_its_opt_record_and_gains_the_option() {
        let cookie = [0, 10, 0, 8, 1, 2, 3, 4, 5, 6, 7, 8];
        let original = with_opt(query("example.com"), &cookie);
        let padded = pad_query(&original);

        assert!(!padded.added_opt);
        assert_eq!(padded.message.len(), QUERY_BLOCK);
        assert_eq!(
            read_u16(&padded.message, 10),
            Some(1),
            "no second OPT record"
        );
        let opt_at = query("example.com").len();
        // Payload size and flags are the client's own.
        assert_eq!(read_u16(&padded.message, opt_at + 3), Some(4096));
        assert_eq!(padded.message[opt_at + 7], 0x80);
        let rdlen = usize::from(read_u16(&padded.message, opt_at + 9).unwrap());
        assert_eq!(opt_at + OPT_FIXED_LEN + rdlen, padded.message.len());
        let rdata = &padded.message[opt_at + OPT_FIXED_LEN..];
        assert_eq!(
            rdata[..cookie.len()],
            cookie,
            "existing options come first, untouched"
        );
        assert_eq!(u16::from_be_bytes([rdata[12], rdata[13]]), OPTION_PADDING);
    }

    #[test]
    fn a_query_already_at_a_block_boundary_still_says_it_is_padded() {
        // 113 octets of query + 11 of OPT + 4 of option header = 128.
        let name = format!("{}.{}", "a".repeat(63), "b".repeat(31));
        let original = query(&name);
        assert_eq!(original.len() + OPT_FIXED_LEN + 4, QUERY_BLOCK);

        let padded = pad_query(&original);
        assert_eq!(padded.message.len(), QUERY_BLOCK);
        let tail = &padded.message[padded.message.len() - 4..];
        assert_eq!(tail, [0, 12, 0, 0], "a padding option of length zero");
    }

    #[test]
    fn what_cannot_be_padded_safely_is_sent_as_it_is() {
        let untouched = |message: Vec<u8>| {
            let padded = pad_query(&message);
            assert_eq!(padded.message, message);
            assert!(!padded.added_opt);
        };

        // Already padded by the client.
        untouched(with_opt(query("example.com"), &[0, 12, 0, 3, 0, 0, 0]));
        // Too short, a truncated name, counts that promise more than is there.
        untouched(vec![0x12, 0x34, 0x01]);
        untouched(vec![
            0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0, 7, b'e', b'x',
        ]);
        let mut lying = query("example.com");
        lying[11] = 1;
        untouched(lying);
        // Trailing octets after the last record.
        let mut trailing = query("example.com");
        trailing.push(0xff);
        untouched(trailing);
        // An OPT record followed by another record (as with TSIG).
        let mut opt_first = with_opt(query("example.com"), &[]);
        opt_first[11] = 2;
        opt_first.extend_from_slice(&[0, 0, 250, 0, 255, 0, 0, 0, 0, 0, 0]);
        untouched(opt_first);
    }

    #[test]
    fn the_opt_record_added_for_padding_is_taken_out_of_the_answer() {
        // An answer: the question, one A record, and the resolver's OPT record.
        let mut answer = query("example.com");
        answer[2] = 0x81;
        answer[3] = 0x80;
        answer[7] = 1;
        answer.extend_from_slice(&[0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 93, 184, 216, 34]);
        let without_opt = answer.clone();
        let with_resolver_opt = with_opt(answer, &[0, 12, 0, 2, 0, 0]);

        assert_eq!(strip_added_opt(with_resolver_opt), without_opt);
        // No OPT record, or nothing that parses: returned as it came.
        assert_eq!(strip_added_opt(without_opt.clone()), without_opt);
        assert_eq!(strip_added_opt(vec![1, 2, 3]), vec![1, 2, 3]);
    }
}
