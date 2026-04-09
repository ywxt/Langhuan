# Book Source Scripts

This directory contains Lua scripts related to Langhuan feed sources.

## Files

- `biquge-tw.lua`
  - A concrete feed source implementation for `biquge.tw`.
- `login-handler-example.lua`
  - A reusable auth snippet that demonstrates the login flow hooks:
    - `login.entry`
    - `login.parse`
    - `login.patch_request`
  - This is a template snippet, not a full feed source by itself.

## Auth Hook Integration

To enable login for an existing source:

1. Copy the `login = { ... }` table from `login-handler-example.lua`.
2. Paste it into your source's final return table alongside `search`, `book_info`, `chapters`, `paragraphs`.
3. Adjust parse rules to match your site (URL params, hidden fields, cookies, CSRF tokens).
4. Use `patch_request` to inject auth data into outbound requests.
