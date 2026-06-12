class_name MarkdownToBBCode
extends RefCounted

static func convert(markdown: String) -> String:
	var text := markdown
	
	# Code blocks: ```language\n code \n``` -> [code]code[/code]
	var code_block_regex := RegEx.new()
	code_block_regex.compile("```(\\w*)\\n?([\\s\\S]*?)```")
	text = code_block_regex.sub(text, "[code]$2[/code]", true)
	
	# Inline code: `code` -> [code]code[/code]
	var inline_code_regex := RegEx.new()
	inline_code_regex.compile("`([^`]+)`")
	text = inline_code_regex.sub(text, "[code]$1[/code]", true)
	
	# Images: ![alt](url "title") -> [img]url[/img]
	var image_regex := RegEx.new()
	image_regex.compile("!\\[([^\\]]*)\\]\\(([^\\s\\)]+)(?:\\s+\"([^\"]+)\")?\\)")
	text = image_regex.sub(text, "[img]$2[/img]", true)
	
	# Links: [text](url) -> [url=url]text[/url]
	var link_regex := RegEx.new()
	link_regex.compile("\\[([^\\]]+)\\]\\(([^\\)]+)\\)")
	text = link_regex.sub(text, "[url=$2]$1[/url]", true)
	
	# Bold: **text** or __text__ -> [b]text[/b]
	var bold_regex1 := RegEx.new()
	bold_regex1.compile("\\*\\*([^\\*]+)\\*\\*")
	text = bold_regex1.sub(text, "[b]$1[/b]", true)
	var bold_regex2 := RegEx.new()
	bold_regex2.compile("__([^_]+)__")
	text = bold_regex2.sub(text, "[b]$1[/b]", true)
	
	# Italic: *text* or _text_ -> [i]text[/i]
	var italic_regex1 := RegEx.new()
	italic_regex1.compile("\\*([^\\*\\s]+[^\\*]*)\\*")
	text = italic_regex1.sub(text, "[i]$1[/i]", true)
	var italic_regex2 := RegEx.new()
	italic_regex2.compile("_([^_\\s]+[^_]*)_")
	text = italic_regex2.sub(text, "[i]$1[/i]", true)
	
	# Blockquotes: > quote -> [indent]quote[/indent]
	var quote_regex := RegEx.new()
	quote_regex.compile("(?m)^>\\s+(.*)$")
	text = quote_regex.sub(text, "[indent]$1[/indent]", true)
	
	# Headers
	var h1_regex := RegEx.new()
	h1_regex.compile("(?m)^#\\s+(.*)$")
	text = h1_regex.sub(text, "[font_size=32][b]$1[/b][/font_size]", true)
	
	var h2_regex := RegEx.new()
	h2_regex.compile("(?m)^##\\s+(.*)$")
	text = h2_regex.sub(text, "[font_size=28][b]$1[/b][/font_size]", true)
	
	var h3_regex := RegEx.new()
	h3_regex.compile("(?m)^###\\s+(.*)$")
	text = h3_regex.sub(text, "[font_size=24][b]$1[/b][/font_size]", true)
	
	var h4_regex := RegEx.new()
	h4_regex.compile("(?m)^####\\s+(.*)$")
	text = h4_regex.sub(text, "[font_size=20][b]$1[/b][/font_size]", true)
	
	var h5_regex := RegEx.new()
	h5_regex.compile("(?m)^#####\\s+(.*)$")
	text = h5_regex.sub(text, "[font_size=18][b]$1[/b][/font_size]", true)
	
	var h6_regex := RegEx.new()
	h6_regex.compile("(?m)^######\\s+(.*)$")
	text = h6_regex.sub(text, "[font_size=16][b]$1[/b][/font_size]", true)
	
	# Unordered Lists: * item or - item -> [ul]item[/ul]
	# We will just replace bullets with ' • ' to avoid breaking bbcode format across lines
	var ul_regex := RegEx.new()
	ul_regex.compile("(?m)^(\\s*)[\\*\\-]\\s+(.*)$")
	text = ul_regex.sub(text, "$1• $2", true)
	
	# Ordered Lists: 1. item -> we keep it as is, maybe add some indent or leave as is
	
	# Tables
	# Let's do a very basic replacement for tables by converting them to monospace or a bbcode table
	var lines = text.split("\n")
	var new_lines: Array[String] = []
	var in_table = false
	var table_cols = 0
	
	for i in range(lines.size()):
		var line = lines[i].strip_edges()
		if line.begins_with("|") and line.ends_with("|"):
			# It's a table row
			var parts = line.split("|", false)
			var is_separator = true
			for p in parts:
				var sp = p.strip_edges()
				if sp.is_empty() or (sp.replace("-", "").replace(":", "") != ""):
					is_separator = false
					break
			
			if is_separator:
				continue
			
			if not in_table:
				in_table = true
				table_cols = parts.size()
				new_lines.append("[table=" + str(table_cols) + "]")
			
			for p in parts:
				new_lines.append("[cell][pad] " + p.strip_edges() + " [/pad][/cell]")
		else:
			if in_table:
				new_lines.append("[/table]")
				in_table = false
			new_lines.append(lines[i])
			
	if in_table:
		new_lines.append("[/table]")
		
	text = "\n".join(new_lines)
	
	# Remove extra empty lines sometimes caused by the Markdown parser
	# but RichTextLabel parses \n as newlines anyway.
	return text
