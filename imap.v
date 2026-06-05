module vmail_imap

pub struct ImapConfig {
pub:
	host            string
	port            int
	username        string
	password        string
	folder          string
	ssl             bool
	starttls        bool
	delete_imported bool
	automatic_tags  bool
	tag             string
}

pub struct ImapCommand {
pub:
	tag  string
	text string
}

pub struct FetchedMessage {
pub:
	seq string
	uid string
	raw string
}

pub fn normalize_config(config ImapConfig) ImapConfig {
	port := if config.port > 0 {
		config.port
	} else {
		if config.ssl { 993 } else { 143 }
	}
	return ImapConfig{
		host:            config.host.trim_space()
		port:            port
		username:        config.username.trim_space()
		password:        config.password
		folder:          if config.folder.trim_space() == '' {
			'INBOX'
		} else {
			config.folder.trim_space()
		}
		ssl:             config.ssl || port == 993
		starttls:        config.starttls && port != 993
		delete_imported: config.delete_imported
		automatic_tags:  config.automatic_tags
		tag:             config.tag.trim_space()
	}
}

pub fn validate_config(config ImapConfig) !ImapConfig {
	clean := normalize_config(config)
	if clean.host == '' {
		return error('imap host is required')
	}
	if clean.username == '' {
		return error('imap username is required')
	}
	if clean.password == '' {
		return error('imap password is required')
	}
	return clean
}

pub fn unread_count_from_search_response(response string) int {
	mut total := 0
	for line in response.split_into_lines() {
		if line.trim_space().to_upper().starts_with('* SEARCH') {
			total += search_ids(line).len
		}
	}
	return total
}

pub fn search_ids(line string) []string {
	parts := line.trim_space().split(' ')
	if parts.len < 2 || parts[0] != '*' || parts[1].to_upper() != 'SEARCH' {
		return []string{}
	}
	mut ids := []string{}
	for part in parts[2..] {
		clean := part.trim_space()
		if clean != '' && clean.bytes().all(it >= `0` && it <= `9`) {
			ids << clean
		}
	}
	return ids
}

pub fn inbox_probe_commands(config ImapConfig) ![]ImapCommand {
	clean := validate_config(config)!
	mut commands := []ImapCommand{}
	mut next_tag := 1
	if clean.starttls {
		commands << ImapCommand{
			tag:  imap_tag(next_tag)
			text: 'STARTTLS'
		}
		next_tag++
	}
	commands << ImapCommand{
		tag:  imap_tag(next_tag)
		text: 'LOGIN ${imap_quote(clean.username)} ${imap_quote(clean.password)}'
	}
	next_tag++
	commands << ImapCommand{
		tag:  imap_tag(next_tag)
		text: 'SELECT ${imap_quote(clean.folder)}'
	}
	next_tag++
	commands << ImapCommand{
		tag:  imap_tag(next_tag)
		text: 'SEARCH UNSEEN'
	}
	return commands
}

pub fn parse_fetch_messages(response string) []FetchedMessage {
	mut messages := []FetchedMessage{}
	mut index := 0
	for index < response.len {
		start := response.index_after('* ', index) or { break }
		fetch_line_end := response.index_after('\r\n', start) or { break }
		header := response[start..fetch_line_end]
		if !header.to_upper().contains(' FETCH ') || !header.contains('{') {
			index = fetch_line_end + 2
			continue
		}
		literal_size := fetch_literal_size(header) or {
			index = fetch_line_end + 2
			continue
		}
		body_start := fetch_line_end + 2
		body_end := body_start + literal_size
		if body_end > response.len {
			break
		}
		messages << FetchedMessage{
			seq: fetch_sequence(header)
			uid: fetch_uid(header)
			raw: response[body_start..body_end]
		}
		index = body_end
	}
	return messages
}

pub fn imap_quote(value string) string {
	escaped := value.replace('\\', '\\\\').replace('"', '\\"')
	return '"${escaped}"'
}

fn fetch_literal_size(header string) ?int {
	open := header.last_index('{') or { return none }
	close := header.index_after('}', open) or { return none }
	raw := header[open + 1..close].trim_space()
	if raw == '' || !raw.bytes().all(it >= `0` && it <= `9`) {
		return none
	}
	return raw.int()
}

fn fetch_sequence(header string) string {
	parts := header.trim_space().split(' ')
	if parts.len >= 2 {
		return parts[1]
	}
	return ''
}

fn fetch_uid(header string) string {
	parts := header.replace('(', ' ').replace(')', ' ').split(' ')
	for i, part in parts {
		if part.to_upper() == 'UID' && i + 1 < parts.len {
			return parts[i + 1].trim_space()
		}
	}
	return ''
}

fn imap_tag(number int) string {
	return 'A${number:03}'
}
