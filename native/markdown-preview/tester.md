 # Mermaid comparison

   ## Flowchart

   ```mermaid
   flowchart TD
       A[Start] --> B{Valid?}
       B -->|Yes| C[Save]
       B -->|No| D[Show error]
   ```

   ## Sequence

   ```mermaid
   sequenceDiagram
       participant User
       participant App
       User->>App: Open document
       App-->>User: Show preview
   ```

   ## State

   ```mermaid
   stateDiagram-v2
       [*] --> Draft
       Draft --> Published: Publish
       Published --> Archived: Archive
   ```

   ## Pie — rendered by MermaidKit; source-only in swift-mermaid

   ```mermaid
   pie
       "Completed" : 8
       "Remaining" : 2
