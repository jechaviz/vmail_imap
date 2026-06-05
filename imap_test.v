module vmail_imap

fn test_search_response_counts_unseen_ids() {
	assert search_ids('* SEARCH 2 4 8') == ['2', '4', '8']
	assert unread_count_from_search_response('* FLAGS (\\Seen)\r\n* SEARCH 2 4 8\r\nA003 OK') == 3
	assert unread_count_from_search_response('* SEARCH\r\nA003 OK') == 0
}

fn test_probe_commands_quote_credentials_and_folder() {
	commands := inbox_probe_commands(ImapConfig{
		host:     'imap.example.test'
		username: 'user"name'
		password: 'pa\\ss'
		folder:   'Team Inbox'
	})!
	assert commands[0].text == 'LOGIN "user\\"name" "pa\\\\ss"'
	assert commands[1].text == 'SELECT "Team Inbox"'
	assert commands[2].text == 'SEARCH UNSEEN'
}

fn test_probe_commands_start_tls_before_login() {
	commands := inbox_probe_commands(ImapConfig{
		host:     'imap.example.test'
		port:     143
		username: 'user'
		password: 'secret'
		starttls: true
	})!
	assert commands[0].text == 'STARTTLS'
	assert commands[1].text == 'LOGIN "user" "secret"'
	assert commands[2].text == 'SELECT "INBOX"'
	assert commands[3].text == 'SEARCH UNSEEN'
}

fn test_fetch_parser_extracts_uid_and_literal_message() {
	raw := 'Subject: Hello\r\n\r\nBody'
	response := '* 7 FETCH (UID 42 RFC822 {22}\r\n${raw})\r\nA004 OK FETCH completed\r\n'
	messages := parse_fetch_messages(response)
	assert messages.len == 1
	assert messages[0].seq == '7'
	assert messages[0].uid == '42'
	assert messages[0].raw == raw
}
