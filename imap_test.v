module vmail_imap

fn test_search_response_counts_unseen_ids() {
	assert search_ids('* SEARCH 2 4 8') == ['2', '4', '8']
	assert unread_count_from_search_response('* FLAGS (\\Seen)\r\n* SEARCH 2 4 8\r\nA003 OK') == 3
	assert unread_count_from_search_response('* SEARCH\r\nA003 OK') == 0
}

fn test_parse_search_ids_collects_response_ids() {
	response := '* FLAGS (\\Seen)\r\n*  SEARCH  2 4  8\r\n* SEARCH 13\r\nA003 OK SEARCH completed\r\n'
	assert parse_search_ids(response) == ['2', '4', '8', '13']
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

fn test_fetch_rfc822_commands_plan_fetch_for_ids() {
	commands := fetch_rfc822_commands(['2', '4', '8'], 4)!
	assert commands.len == 1
	assert commands[0].tag == 'A004'
	assert commands[0].text == 'FETCH 2,4,8 (UID RFC822)'
}

fn test_delete_message_commands_mark_deleted_and_expunge() {
	commands := delete_message_commands(['2', '4', '8'], 5)!
	assert commands.len == 2
	assert commands[0].tag == 'A005'
	assert commands[0].text == 'STORE 2,4,8 +FLAGS.SILENT (\\Deleted)'
	assert commands[1].tag == 'A006'
	assert commands[1].text == 'EXPUNGE'
}

fn test_delete_uid_commands_mark_deleted_by_uid_and_expunge() {
	commands := delete_uid_commands(['11', '12'], 7)!
	assert commands.len == 2
	assert commands[0].tag == 'A007'
	assert commands[0].text == 'UID STORE 11,12 +FLAGS.SILENT (\\Deleted)'
	assert commands[1].tag == 'A008'
	assert commands[1].text == 'EXPUNGE'
}

fn test_command_planners_skip_empty_ids_and_reject_invalid_ids() {
	assert fetch_rfc822_commands([' ', '9'], 0)![0].text == 'FETCH 9 (UID RFC822)'
	assert delete_message_commands([], 2)!.len == 0
	fetch_rfc822_commands(['2', 'abc'], 1) or {
		assert err.msg() == 'imap message id must be numeric'
		return
	}
	assert false
}
