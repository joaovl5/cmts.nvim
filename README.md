# cmts.nvim

This allows for highlighting strings as if they're files from other languages,
regardless of language, by specifying the string's filetype in an immediately preceding comment.

Credits to `hmts.nvim`, which this code was hard-forked from.

## Usage

We'll assume Tree-sitter parsers already exist, and the plugin was already loaded with some plugin manager.

Put a comment with only the language name immediately before the string or
its single-line declaration. Use the comment syntax of the host language.

```nix
# bash
''
  echo 'hi!'
''
```

```python
# sql
query = """SELECT * FROM users"""
```

```javascript
// css
const styles = `body { color: red; }`;
```

```lua
-- bash
local script = [=[echo 'hi!']=]
```

(the names must match Neovim filetypes exactly)

## Disclaimer

This is a quick plugin made for my own use-cases, and I used LLMs for assistence, use it at your own peril.
