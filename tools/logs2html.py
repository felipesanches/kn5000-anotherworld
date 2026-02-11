#!/usr/bin/env python3
"""Convert Claude Code JSONL conversation logs to a static HTML viewer.

Usage: python3 logs2html.py logs/*.jsonl -o logs/index.html
"""

import json
import os
import re
import sys
import html
import argparse
from datetime import datetime, timezone


def strip_system_tags(text):
    """Remove <system-reminder>...</system-reminder> and similar tags."""
    text = re.sub(r'<system-reminder>.*?</system-reminder>', '', text, flags=re.DOTALL)
    text = re.sub(r'<local-command-caveat>.*?</local-command-caveat>', '', text, flags=re.DOTALL)
    text = re.sub(r'<local-command-stdout>.*?</local-command-stdout>', '', text, flags=re.DOTALL)
    text = re.sub(r'<command-name>.*?</command-name>', '', text, flags=re.DOTALL)
    text = re.sub(r'<command-message>.*?</command-message>', '', text, flags=re.DOTALL)
    text = re.sub(r'<command-args>.*?</command-args>', '', text, flags=re.DOTALL)
    return text.strip()


def summarize_tool_input(name, inp):
    """Create a short summary of a tool call."""
    if name == 'Bash':
        return inp.get('command', '')
    elif name == 'Read':
        path = inp.get('file_path', '')
        parts = []
        if path:
            parts.append(os.path.basename(path))
        offset = inp.get('offset')
        limit = inp.get('limit')
        if offset:
            parts.append(f'L{offset}')
        if limit:
            parts.append(f'+{limit}')
        return ' '.join(parts)
    elif name == 'Edit':
        path = inp.get('file_path', '')
        old = inp.get('old_string', '')[:60]
        return f"{os.path.basename(path)}"
    elif name == 'Write':
        return os.path.basename(inp.get('file_path', ''))
    elif name == 'Glob':
        return inp.get('pattern', '')
    elif name == 'Grep':
        pattern = inp.get('pattern', '')
        path = inp.get('path', '')
        return f"{pattern}" + (f" in {os.path.basename(path)}" if path else '')
    elif name == 'WebFetch':
        return inp.get('url', '')
    elif name == 'Task':
        return inp.get('description', '') or inp.get('prompt', '')[:80]
    elif name == 'WebSearch':
        return inp.get('query', '')
    return json.dumps(inp)[:100]


def extract_tool_result_text(content_blocks):
    """Extract text from tool_result blocks."""
    results = []
    for block in content_blocks:
        if block.get('type') == 'tool_result':
            inner = block.get('content', '')
            if isinstance(inner, str):
                text = inner
            elif isinstance(inner, list):
                text = '\n'.join(b.get('text', '') for b in inner if b.get('type') == 'text')
            else:
                text = str(inner)
            text = strip_system_tags(text)
            if text.strip():
                results.append(text[:500])
    return results


def parse_session(path):
    """Parse a JSONL log file into a structured session."""
    filename = os.path.basename(path)
    # Extract date and description from filename
    m = re.match(r'(\d{4}-\d{2}-\d{2})_(.+)\.jsonl$', filename)
    if m:
        date = m.group(1)
        description = m.group(2).replace('-', ' ').replace('_', ' ').title()
    else:
        date = ''
        description = filename

    messages = []
    with open(path) as f:
        for line in f:
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_type = obj.get('type', '')
            if msg_type not in ('user', 'assistant'):
                continue

            # Skip isMeta messages
            if obj.get('isMeta'):
                continue

            timestamp = obj.get('timestamp', '')
            msg = obj.get('message', {})
            content = msg.get('content', '')

            if msg_type == 'user':
                if isinstance(content, str):
                    text = strip_system_tags(content)
                    if not text:
                        continue
                    messages.append({
                        'role': 'user',
                        'text': text,
                        'ts': timestamp,
                    })
                elif isinstance(content, list):
                    # Check for tool_result blocks (skip) vs text blocks
                    has_tool_result = any(b.get('type') == 'tool_result' for b in content)
                    if has_tool_result:
                        continue  # Tool results are shown as part of assistant flow
                    text_parts = []
                    for block in content:
                        if block.get('type') == 'text':
                            t = strip_system_tags(block.get('text', ''))
                            if t:
                                text_parts.append(t)
                    if text_parts:
                        messages.append({
                            'role': 'user',
                            'text': '\n'.join(text_parts),
                            'ts': timestamp,
                        })

            elif msg_type == 'assistant':
                if not isinstance(content, list):
                    continue

                text_parts = []
                tool_calls = []
                thinking = None

                for block in content:
                    btype = block.get('type', '')
                    if btype == 'text':
                        t = strip_system_tags(block.get('text', ''))
                        if t:
                            text_parts.append(t)
                    elif btype == 'tool_use':
                        tool_name = block.get('name', '')
                        tool_input = block.get('input', {})
                        tool_calls.append({
                            'name': tool_name,
                            'summary': summarize_tool_input(tool_name, tool_input),
                        })
                    elif btype == 'thinking':
                        t = block.get('thinking', '')
                        if t:
                            # Truncate thinking to keep HTML manageable
                            if len(t) > 300:
                                t = t[:300] + '...'
                            thinking = t

                # Skip empty assistant messages (no text, no tools, no thinking)
                if not text_parts and not tool_calls and not thinking:
                    continue

                entry = {
                    'role': 'assistant',
                    'ts': timestamp,
                }
                if text_parts:
                    entry['text'] = '\n'.join(text_parts)
                if tool_calls:
                    entry['tools'] = tool_calls
                if thinking:
                    entry['thinking'] = thinking

                # Merge consecutive tool-only messages into previous assistant message
                if messages and messages[-1].get('role') == 'assistant' and not text_parts:
                    prev = messages[-1]
                    if tool_calls:
                        prev.setdefault('tools', []).extend(tool_calls)
                    if thinking and 'thinking' not in prev:
                        prev['thinking'] = thinking
                    elif thinking:
                        prev['thinking'] += '\n\n' + thinking
                    continue

                messages.append(entry)

    return {
        'filename': filename,
        'date': date,
        'title': description,
        'messages': messages,
    }


def generate_html(sessions):
    """Generate a self-contained HTML page."""
    sessions_json = json.dumps(sessions, ensure_ascii=False)

    return f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Another World VM — Development Log</title>
<style>
:root {{
  --bg: #0a0a0f;
  --surface: #12121a;
  --surface2: #1a1a26;
  --border: #2a2a3a;
  --text: #c8c8d8;
  --text-dim: #808098;
  --accent: #6e8cef;
  --accent-dim: #3a4a7a;
  --user-bg: #1a2238;
  --user-border: #2a3a5a;
  --assistant-bg: #141420;
  --tool-bg: #0f1418;
  --tool-border: #1a2a2a;
  --thinking-bg: #18141a;
  --thinking-border: #2a1a3a;
  --green: #5ab87a;
  --orange: #d8a040;
  --red: #c85050;
}}
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{
  font-family: 'SF Mono', 'Cascadia Code', 'Fira Code', 'JetBrains Mono', monospace;
  background: var(--bg);
  color: var(--text);
  font-size: 13px;
  line-height: 1.6;
}}
.layout {{
  display: flex;
  height: 100vh;
}}
.sidebar {{
  width: 280px;
  min-width: 280px;
  background: var(--surface);
  border-right: 1px solid var(--border);
  overflow-y: auto;
  padding: 16px 0;
}}
.sidebar h1 {{
  font-size: 14px;
  font-weight: 600;
  color: var(--accent);
  padding: 0 16px 12px;
  border-bottom: 1px solid var(--border);
  margin-bottom: 8px;
  letter-spacing: 0.5px;
}}
.sidebar h1 span {{
  display: block;
  font-size: 11px;
  color: var(--text-dim);
  font-weight: 400;
  margin-top: 2px;
}}
.session-item {{
  padding: 10px 16px;
  cursor: pointer;
  border-left: 3px solid transparent;
  transition: all 0.15s;
}}
.session-item:hover {{
  background: var(--surface2);
}}
.session-item.active {{
  background: var(--surface2);
  border-left-color: var(--accent);
}}
.session-item .date {{
  font-size: 11px;
  color: var(--text-dim);
}}
.session-item .title {{
  font-size: 12px;
  color: var(--text);
  margin-top: 2px;
}}
.session-item .stats {{
  font-size: 10px;
  color: var(--text-dim);
  margin-top: 4px;
}}
.main {{
  flex: 1;
  overflow-y: auto;
  padding: 24px 32px;
  max-width: 900px;
}}
.session-header {{
  margin-bottom: 24px;
  padding-bottom: 16px;
  border-bottom: 1px solid var(--border);
}}
.session-header h2 {{
  font-size: 18px;
  color: var(--accent);
  font-weight: 600;
}}
.session-header .meta {{
  font-size: 11px;
  color: var(--text-dim);
  margin-top: 4px;
}}
.message {{
  margin-bottom: 16px;
  border-radius: 6px;
  overflow: hidden;
}}
.message .role-label {{
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 1px;
  padding: 6px 12px;
}}
.message.user .role-label {{
  color: var(--accent);
  background: var(--user-border);
}}
.message.assistant .role-label {{
  color: var(--green);
  background: rgba(90, 184, 122, 0.1);
}}
.message .content {{
  padding: 12px;
  white-space: pre-wrap;
  word-wrap: break-word;
}}
.message.user {{
  background: var(--user-bg);
  border: 1px solid var(--user-border);
}}
.message.assistant {{
  background: var(--assistant-bg);
  border: 1px solid var(--border);
}}
.tool-calls {{
  margin: 8px 12px 12px;
}}
.tool-call {{
  background: var(--tool-bg);
  border: 1px solid var(--tool-border);
  border-radius: 4px;
  margin-bottom: 4px;
  font-size: 12px;
}}
.tool-call summary {{
  padding: 4px 8px;
  cursor: pointer;
  color: var(--orange);
  user-select: none;
}}
.tool-call summary:hover {{
  background: rgba(216, 160, 64, 0.05);
}}
.tool-call .tool-detail {{
  padding: 6px 8px;
  color: var(--text-dim);
  border-top: 1px solid var(--tool-border);
  white-space: pre-wrap;
  word-break: break-all;
  max-height: 300px;
  overflow-y: auto;
}}
.thinking-block {{
  margin: 8px 12px;
}}
.thinking-block details {{
  background: var(--thinking-bg);
  border: 1px solid var(--thinking-border);
  border-radius: 4px;
}}
.thinking-block summary {{
  padding: 4px 8px;
  cursor: pointer;
  color: #a070c0;
  font-size: 11px;
  user-select: none;
}}
.thinking-block .thinking-content {{
  padding: 8px;
  color: var(--text-dim);
  font-size: 11px;
  border-top: 1px solid var(--thinking-border);
  white-space: pre-wrap;
  word-wrap: break-word;
  max-height: 400px;
  overflow-y: auto;
}}
.tool-badge {{
  display: inline-block;
  background: rgba(216, 160, 64, 0.15);
  color: var(--orange);
  font-size: 10px;
  padding: 1px 6px;
  border-radius: 3px;
  font-weight: 600;
  margin-right: 4px;
}}
.empty {{
  color: var(--text-dim);
  text-align: center;
  margin-top: 100px;
  font-size: 14px;
}}
/* Markdown-ish formatting for assistant text */
.content code {{
  background: rgba(110, 140, 239, 0.1);
  padding: 1px 4px;
  border-radius: 3px;
  font-size: 12px;
}}
.content strong {{
  color: #e0e0f0;
}}
::-webkit-scrollbar {{
  width: 6px;
}}
::-webkit-scrollbar-track {{
  background: transparent;
}}
::-webkit-scrollbar-thumb {{
  background: var(--border);
  border-radius: 3px;
}}
</style>
</head>
<body>
<div class="layout">
  <div class="sidebar">
    <h1>Another World VM<span>KN5000 Development Log</span></h1>
    <div id="session-list"></div>
  </div>
  <div class="main" id="main">
    <div class="empty">Select a session from the sidebar</div>
  </div>
</div>
<script>
const SESSIONS = {sessions_json};

function escapeHtml(s) {{
  const div = document.createElement('div');
  div.textContent = s;
  return div.innerHTML;
}}

function formatText(text) {{
  // Basic markdown: **bold**, `code`, ```code blocks```
  let h = escapeHtml(text);
  h = h.replace(/```(\\w*)\\n([\\s\\S]*?)```/g, '<pre style="background:rgba(255,255,255,0.03);padding:8px;border-radius:4px;margin:4px 0;overflow-x:auto"><code>$2</code></pre>');
  h = h.replace(/`([^`]+)`/g, '<code>$1</code>');
  h = h.replace(/\\*\\*([^*]+)\\*\\*/g, '<strong>$1</strong>');
  return h;
}}

function renderSessionList() {{
  const list = document.getElementById('session-list');
  list.innerHTML = '';
  SESSIONS.forEach((s, i) => {{
    const userMsgs = s.messages.filter(m => m.role === 'user').length;
    const assistantMsgs = s.messages.filter(m => m.role === 'assistant').length;
    const toolCount = s.messages.reduce((n, m) => n + (m.tools ? m.tools.length : 0), 0);
    const div = document.createElement('div');
    div.className = 'session-item';
    div.innerHTML = `
      <div class="date">${{escapeHtml(s.date)}}</div>
      <div class="title">${{escapeHtml(s.title)}}</div>
      <div class="stats">${{userMsgs}} user · ${{assistantMsgs}} assistant · ${{toolCount}} tools</div>
    `;
    div.onclick = () => renderSession(i);
    list.appendChild(div);
  }});
}}

function renderSession(index) {{
  // Update active state
  document.querySelectorAll('.session-item').forEach((el, i) => {{
    el.classList.toggle('active', i === index);
  }});

  const s = SESSIONS[index];
  const main = document.getElementById('main');
  let html = `
    <div class="session-header">
      <h2>${{escapeHtml(s.title)}}</h2>
      <div class="meta">${{escapeHtml(s.date)}} · ${{escapeHtml(s.filename)}}</div>
    </div>
  `;

  for (const msg of s.messages) {{
    html += `<div class="message ${{msg.role}}">`;
    html += `<div class="role-label">${{msg.role}}</div>`;

    if (msg.thinking) {{
      html += `<div class="thinking-block"><details>
        <summary>Thinking</summary>
        <div class="thinking-content">${{escapeHtml(msg.thinking)}}</div>
      </details></div>`;
    }}

    if (msg.text) {{
      html += `<div class="content">${{formatText(msg.text)}}</div>`;
    }}

    if (msg.tools && msg.tools.length) {{
      html += `<div class="tool-calls">`;
      for (const tool of msg.tools) {{
        html += `<details class="tool-call">
          <summary><span class="tool-badge">${{escapeHtml(tool.name)}}</span> ${{escapeHtml(tool.summary).substring(0, 120)}}</summary>
          <div class="tool-detail">${{escapeHtml(tool.summary)}}</div>
        </details>`;
      }}
      html += `</div>`;
    }}

    html += `</div>`;
  }}

  main.innerHTML = html;
  main.scrollTop = 0;
}}

renderSessionList();
// Auto-select last session
if (SESSIONS.length > 0) {{
  renderSession(SESSIONS.length - 1);
}}
</script>
</body>
</html>'''


def main():
    parser = argparse.ArgumentParser(description='Convert Claude Code JSONL logs to HTML')
    parser.add_argument('files', nargs='+', help='JSONL log files')
    parser.add_argument('-o', '--output', default='logs/index.html', help='Output HTML file')
    args = parser.parse_args()

    sessions = []
    for path in sorted(args.files):
        if not os.path.exists(path):
            print(f"Warning: {path} not found, skipping", file=sys.stderr)
            continue
        print(f"Processing {os.path.basename(path)}...", file=sys.stderr)
        session = parse_session(path)
        sessions.append(session)
        msg_count = len(session['messages'])
        tool_count = sum(len(m.get('tools', [])) for m in session['messages'])
        print(f"  -> {msg_count} messages, {tool_count} tool calls", file=sys.stderr)

    html = generate_html(sessions)
    with open(args.output, 'w') as f:
        f.write(html)
    print(f"\nWrote {args.output} ({len(html):,} bytes)", file=sys.stderr)


if __name__ == '__main__':
    main()
