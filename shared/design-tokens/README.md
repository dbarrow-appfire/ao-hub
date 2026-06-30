# Shared Design Tokens

Single CSS custom properties file loaded by both Dobase and Twenty for visual consistency.

## Usage

- **Dobase:** Copy or symlink into `app/assets/stylesheets/` and link in `application.html.erb`
- **Twenty:** `@import url('/shared_tokens.css')` in `packages/twenty-front/src/index.css`
- **SDK app:** Reference via `var(--token-name)` in inline styles

## Documentation

- [Design Token Specification](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85753857)
- [Dobase Styling Integration](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85065730)
- [Twenty Styling Integration](https://danappfire.atlassian.net/wiki/spaces/DEV/pages/85786625)
