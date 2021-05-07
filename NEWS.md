# Release Notes

Planned for v0.8.0

- Specialize interpolation within Javascript valued attributes
- Provide better CSS serialization within `<style>` tag

## v0.7.0

- Adding `<span>` as wrapper for default content interpolation
- Support `"text/javascript"` serialization within `<script>` tag
- Support `"text/css"` serialization within `<style>` tag
- Remove experimental support for nested non-standard string literals
- Documented how `@htl_str` can be used for dynamic templates

# v0.6.0

- Improved documentation
- Fixed lots of edge cases
- Interpolation within comment blocks

# v0.5.0

- Ensured that unicode works for templates

# v0.4.0

- Separate string literal vs macro
- No longer export string literal by default

# v0.3.0

- General refactoring for extensibility
- Converted to use an escape proxy
- Simplify attribute dispatch

# v0.2.0

- Added benchmarking test
- Significant perforamance enhancements
- Implemented via closures rather than objects
