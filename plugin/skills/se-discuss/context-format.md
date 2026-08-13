# GLOSSARY.md Format

Dictionary of project-specific terms. Not a spec, scratch pad, or decision log.

## Structure

```md
# {Context Name}

{One or two sentence description of what this context is and why it exists.}

## Language

**Order**:
{A one or two sentence description of the term}
_Avoid_: Purchase, transaction

**Invoice**:
A request for payment sent to a customer after delivery.
_Avoid_: Bill, payment request

**Customer**:
A person or organization that places orders.
_Avoid_: Client, buyer, account
```

## Rules

- **Be opinionated.** When multiple words exist for the same concept, pick the best one and list the others under `_Avoid_`.
- **Keep definitions tight.** One or two sentences max. Define what it IS, not what it does.
- **Only include terms specific to this project's context.** General programming concepts (timeouts, error types, utility patterns) don't belong even if the project uses them extensively. Before adding a term, ask: is this a concept unique to this context, or a general programming concept? Only the former belongs.
- **Group terms under subheadings** when natural clusters emerge. If all terms belong to a single cohesive area, a flat list is fine.

## Single vs multi-context repos

**Single context (most repos):** One `GLOSSARY.md` at the repo root.

**Multiple contexts:** A `GLOSSARY-MAP.md` at the repo root lists the contexts, where they live, and how they relate. Each context’s dictionary is `GLOSSARY.md` beside that context’s code:

```md
# Context Map

## Contexts

- [Ordering](./src/ordering/GLOSSARY.md) — receives and tracks customer orders
- [Billing](./src/billing/GLOSSARY.md) — generates invoices and processes payments
- [Fulfillment](./src/fulfillment/GLOSSARY.md) — manages warehouse picking and shipping

## Relationships

- **Ordering → Fulfillment**: Ordering emits `OrderPlaced` events; Fulfillment consumes them to start picking
- **Fulfillment → Billing**: Fulfillment emits `ShipmentDispatched` events; Billing consumes them to generate invoices
- **Ordering ↔ Billing**: Shared types for `CustomerId` and `Money`
```

## Read vs write

**Write:** `GLOSSARY.md` / `GLOSSARY-MAP.md` at the locations above. Lazy: glossary on first term, map on first multi-context need — even if `CONTEXT*` already exist. Do not automatically write `CONTEXT.md` / `CONTEXT-MAP.md`. No copy CONTEXT → GLOSSARY. User asks to edit `CONTEXT*` → follow.

**Read:** union `GLOSSARY.md`+`CONTEXT.md` and `GLOSSARY-MAP.md`+`CONTEXT-MAP.md`. GLOSSARY wins; CONTEXT fills gaps.

Infer structure:

- `GLOSSARY-MAP.md` and/or `CONTEXT-MAP.md` → multi-context; union maps, then each context’s dictionaries
- Else root `GLOSSARY.md` and/or `CONTEXT.md` → single context; union
- Else create root `GLOSSARY.md` on first term

Unclear which context → ask.
