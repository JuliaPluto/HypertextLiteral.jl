# Release Notes

## v0.9.0

- Removing Javscript treatment from `on` attributes
- Exporting `htl` non-standard string literal
- In `htl` literal, doubling of `$` escapes `$`
- Continued review of documentation

## v0.8.0

- Restructructed documentation to improve navigation
- Specialize interpolation within Javascript valued attributes
- Ensure that `@htl` is passed a string literal (Fixed #11)
- Provide better CSS serialization within `<style>` tag

## v0.7.0

- Adding `<span>` as wrapper for default content interpolation
- Support `"text/javascript"` serialization within `<script>` tag (#10)
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
