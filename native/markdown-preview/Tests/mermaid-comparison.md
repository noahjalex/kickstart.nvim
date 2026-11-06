# Native Mermaid comparison

All four sections should show centered, bounded diagrams without duplicate source. These are deliberately larger than the two-node smoke test: compare branching, long edges, labels, and narrow-window readability. Click each diagram for a floating vector panel and Copy Source.

## 1. Order processing — branching flowchart

```mermaid
flowchart TD
    Start[Receive order] --> Auth{Authenticated?}
    Auth -->|No| Reject[Reject request]
    Auth -->|Yes| Validate[Validate order]
    Validate --> Stock{In stock?}
    Stock -->|No| Wait[Backorder queue]
    Wait --> Notify[Notify customer]
    Stock -->|Yes| Reserve[Reserve inventory]
    Reserve --> Price[Calculate total]
    Price --> Pay{Payment accepted?}
    Pay -->|No| Release[Release inventory]
    Release --> Notify
    Pay -->|Yes| Save[Save order]
    Save --> Events[Publish order event]
    Events --> Pick[Pick items]
    Events --> Receipt[Send receipt]
    Pick --> Pack[Pack shipment]
    Pack --> Ship[Create shipping label]
    Ship --> Track[Send tracking link]
    Track --> Delivered{Delivered?}
    Delivered -->|No| Support[Support followup]
    Delivered -->|Yes| Complete[Complete order]
    Receipt --> Audit[Append audit log]
    Complete --> Audit
    Reject --> Audit
```

## 2. Checkout — multi-participant sequence

```mermaid
sequenceDiagram
    participant User
    participant Web
    participant API
    participant Stock
    participant Bank
    participant Queue
    participant Mail
    User->>Web: Submit checkout
    Web->>API: Create order
    API->>Stock: Reserve items
    Stock-->>API: Reservation token
    API->>Bank: Authorize payment
    Bank-->>API: Authorization accepted
    API->>Queue: Order created
    API-->>Web: Order ID and receipt
    Web-->>User: Show confirmation
    Queue->>Stock: Begin fulfillment
    Queue->>Mail: Send receipt
    Mail-->>User: Receipt delivered
    Stock->>Queue: Shipment ready
    Queue->>Mail: Send tracking link
    Mail-->>User: Tracking details
    User->>Web: Check order status
    Web->>API: Fetch order
    API->>Stock: Fetch shipment
    Stock-->>API: In transit
    API-->>Web: Current status
    Web-->>User: Show tracking
```

## 3. Document publishing — state machine

```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Validating: Submit
    Validating --> Draft: Invalid
    Validating --> Reviewing: Valid
    Reviewing --> ChangesRequested: Request edits
    ChangesRequested --> Draft: Edit
    Reviewing --> Approved: Approve
    Approved --> Scheduled: Set date
    Approved --> Publishing: Publish now
    Scheduled --> Publishing: Timer fires
    Scheduled --> Draft: Cancel schedule
    Publishing --> Published: Success
    Publishing --> Failed: Error
    Failed --> Publishing: Retry
    Failed --> Draft: Revise
    Published --> Draft: New revision
    Published --> Archived: Archive
    Archived --> Published: Restore
    Archived --> [*]
```

## 4. Delivery pipeline — wide flowchart

```mermaid
flowchart LR
    Commit[Commit] --> Lint[Lint]
    Commit --> Types[Type check]
    Commit --> Unit[Unit tests]
    Lint --> Build[Build package]
    Types --> Build
    Unit --> Build
    Build --> Scan[Security scan]
    Build --> Integration[Integration tests]
    Scan --> Stage[Deploy staging]
    Integration --> Stage
    Stage --> Smoke[Smoke tests]
    Smoke --> Review[Release approval]
    Review --> Canary[Canary rollout]
    Canary --> Metrics{Metrics healthy?}
    Metrics -->|No| Rollback[Rollback]
    Metrics -->|Yes| Rollout[Full rollout]
    Rollout --> Production[Production]
    Production --> Observe[Observe service]
    Observe --> Incident{Regression?}
    Incident -->|Yes| Rollback
    Incident -->|No| Done[Release complete]
    Rollback --> Report[Write incident report]
    Report --> Commit
```

## Manual checks

- All four diagrams render centered with rounded boundaries; source is hidden by default.
- Resize narrow → wide → narrow. Check clipped arrows, label collisions, aspect ratio, and centering.
- Click each diagram. Check that its resizable panel floats over the article, with sharp labels when zoomed.
- The diagram fills the panel without a helper bar. Scroll to zoom; click-and-drag to pan. Test ⌘0, ⌘+/−, and pinch.
- Right-click the diagram and choose Copy Source. Paste into an unsaved scratch buffer and compare whitespace and line endings with the fence content.
- Reopen and dismiss with Escape, ⌘W, clicking the article, and clicking another app. Outside clicks should still work, and the article must remain open.
- Change one label in this document without saving. The preview should update.
- No pie or sequence auto-numbering is used, so the known dependency crash guards should not suppress these diagrams.
