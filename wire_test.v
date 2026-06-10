module vmail_imap

struct MockImapStream {
mut:
	data string
	pos  int
}

fn (mut stream MockImapStream) read(mut buffer []u8) !int {
	if stream.pos >= stream.data.len || buffer.len == 0 {
		return 0
	}
	remaining := stream.data.len - stream.pos
	read_count := if remaining < buffer.len { remaining } else { buffer.len }
	for i in 0 .. read_count {
		buffer[i] = stream.data[stream.pos + i]
	}
	stream.pos += read_count
	return read_count
}

fn (mut stream MockImapStream) write_string(value string) !int {
	return value.len
}

fn test_read_response_keeps_tag_like_lines_inside_fetch_literal() {
	raw := 'Subject: Tag collision\r\n\r\nhello\r\nA004 OK not a tagged response\r\nbye'
	response := '* 1 FETCH (UID 99 RFC822 {${raw.len}}\r\n${raw})\r\nA004 OK FETCH completed\r\n'
	mut stream := MockImapStream{
		data: response
	}
	read := read_response(mut stream, 'A004')!
	messages := parse_fetch_messages(read)
	assert read == response
	assert messages.len == 1
	assert messages[0].uid == '99'
	assert messages[0].raw == raw
}
