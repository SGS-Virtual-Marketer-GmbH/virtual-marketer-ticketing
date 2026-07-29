# Virtual Marketer Ticketing

A web-based helpdesk and customer support platform, streamlining customer
communication across email, chat, telephone and social media.

This is the helpdesk that backs the Virtual Marketer customer care stack. It
replaces the previous Zendesk deployment and is driven end-to-end by the
`denta-care-agent` AI pipeline (classification, enrichment, reply drafting and
write-back).

## Built on Zammad

Virtual Marketer Ticketing is a **rebranded fork of [Zammad](https://github.com/zammad/zammad)**,
an open-source helpdesk created by the [Zammad Foundation](https://zammad-foundation.org/)
and developed by [Zammad GmbH](https://zammad.com/) together with its community.

It is used here under the GNU AGPL v3. See [NOTICE.md](NOTICE.md) and
[LICENSE](LICENSE). Upstream copyright notices are retained throughout the
source, as the licence requires. Only branding — logo, wordmark, favicon,
product name and outbound mail headers — has been changed; the application
code is Zammad's.

We are not affiliated with, nor endorsed by, the Zammad Foundation or Zammad
GmbH. Per the [Zammad trademark policy](https://zammad-foundation.org/policy/),
the Zammad name and logo are not used as this product's identity.

## Branding

Branding assets are **generated, never hand-edited**, so they survive an
upstream merge:

```sh
python3 contrib/branding/generate.py
```

One vector source (`contrib/branding/src/logo.svg`) plus Zammad's own Fira Sans
produces the colour mark, the theme-adaptive flat mark, the "Virtual Marketer"
wordmark, the combined logo, the favicon/PWA raster set, and the three logo
symbols inside the `icons.svg` sprite. Re-run it after merging upstream.

See [contrib/branding/README.md](contrib/branding/README.md) for what it touches
and why.

## Running locally

```sh
docker compose -f docker-compose.local.yml up -d --build
```

Serves on <http://localhost:8090>. This builds the app image from this source
tree rather than pulling the upstream Zammad image, and omits Elasticsearch to
keep the local footprint small — search is degraded without it, and attachment
content is not indexed.

> **Do not complete the setup wizard** on an instance you intend to migrate
> Zendesk data into. Zammad's Zendesk importer refuses to run once
> `system_init_done` is set, and differential re-imports are not supported.
> Import first; the import initialises the instance.

## Further information

Upstream documentation applies unchanged:

- [Admin & install docs](https://docs.zammad.org)
- [REST API](https://docs.zammad.org/en/latest/api/intro.html)
- [Developer manual](/doc/developer_manual/index.md)
- [Zendesk migration](https://docs.zammad.org/en/latest/migration/zendesk.html)
- Security vulnerabilities: see [SECURITY.md](SECURITY.md)
