# Architecture diagram style guide

Reusable styling for the interactive architecture diagram ([../architecture.html](../architecture.html) is the reference rendering).

Files:
- `architecture.css`: all design tokens and component styles.
- `architecture.template.html`: skeleton with placeholders and one example of every pattern.

## Regenerating for a new scope

1. Copy both files into a new folder and rename the template to `architecture.html`.
2. Gather the inventory, read-only and with no secrets:
   - Resource group: `az graph query -q "resources | where resourceGroup =~ '<rg>' | project name, type, location, sku, properties" --subscriptions <sub>`
   - Subscription: same query without the RG filter, grouped by `resourceGroup`. Draw one `.rg` boundary per group.
   - Also pull: private endpoints (`microsoft.network/privateendpoints`), VNets and subnets, role assignments, diagnostic settings, and public-network and firewall settings per resource.
3. Fill the header chips, callout (only for real caveats), cards, paths, flow list, boundary notes, and inventory table.
4. Check every claim against live config, not only IaC. Mark anything not deployed with `.optional` and the dashed legend entry.
5. Open in a browser, test every layer toggle, and confirm no text overflows its card.

## Design tokens

| Token | Value | Use |
|---|---|---|
| `--bg` | `#0b1020` | page background |
| `--panel` | `#111a2d` | panels |
| `--border` | `#293852` | outlines |
| `--text` / `--muted` | `#edf3ff` / `#9aabc7` | text |
| `--cyan` | `#43d9e8` | data flow, compute/web cards |
| `--blue` | `#83aaff` | network association |
| `--violet` | `#c1a2ff` | identity, workflow cards |
| `--green` | `#73e0b0` | monitoring |
| `--amber` | `#ffc875` | callouts, storage cards |

## Layers

Each SVG group carries `data-layer="data|network|identity|monitor"`. Toolbar toggles match by name. To add a layer, add a toolbar checkbox with `data-toggle="<name>"` and a colour variable. Groups without `data-layer` are always visible.

## SVG conventions

- Canvas `viewBox="0 0 1760 1050"` on a roomy grid: 280px-wide cards with 70px gutters, callers above the `.rg` box, subnets 25px inside the VNet, and at least 12px between stacked cards. Keep text 16px from card edges. Run connectors through the gutters and shared channels (e.g. x=1285 for identity, x=1685 for monitoring) rather than across cards, and accept a crossing only when rerouting would add clutter.
- Boundaries: `.rg` (dashed grey) wraps the scope, `.vnet` (dashed teal) wraps the network, `.subnet` sits inside it (`.subnet-pe` for private endpoint subnets). Corner radius 15–22.
- Cards: `rx="16"`, class `card` plus a family colour (`cyan-card` compute/web, `violet-card` workflow/identity, `amber-card` storage, `green-card` monitoring). Contents: 28px icon tile, `.svg-title`, `.svg-copy` lines, optional `.badge` pill with `.badge-text` in caps.
- Typography: `.svg-label` (caps section labels), `.svg-title`, `.svg-copy`, `.svg-mini`.
- Paths: orthogonal `H`/`V` segments only. Classes `path-data` (solid cyan), `path-network` (solid blue), `path-identity` (dotted violet), `path-monitor` (dashed green). Draw paths before cards so cards overlap the line ends.
- Flow labels: `.label-bg` rect (`rx="7"`, 21px high) plus centred `.flow-label` text, placed on the path and in the same layer.
- Optional or undeployed resources: `.optional` (dashed grey). Add an "Optional / not deployed" legend entry only when one is drawn.

## Content rules

- Include resource names but never keys, SAS tokens, connection strings, or app setting values.
- State public and private exposure explicitly (badges such as `PUBLIC INGRESS` or `PRIVATE + FIREWALL`).
- Keep the "Key request paths" list and the inventory table consistent with the diagram.
- Put the generation basis (live inventory vs. IaC) in the footer.
