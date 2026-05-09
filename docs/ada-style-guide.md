# Ada Coding Standard for Termicap

## Naming Conventions

| Entity | Convention | Example |
|--------|-----------|---------|
| Package | Mixed_Case | `My_Package.Sub_Package` |
| Type | Mixed_Case | `Command_Type` |
| Constant | ALL_CAPS | `MAX_BUFFER_SIZE` |
| Variable | Mixed_Case | `Current_Index` |
| Subprogram | Mixed_Case | `Process_Input` |
| Parameter | Mixed_Case | `Input_Buffer` |
| Access type | `_Ptr` suffix | `Command_Ptr` |
| Exception | `E_` prefix | `E_Invalid_Input` |
| Interface | `I_` prefix | `I_Printable` |
| Abstract type | `Abstract_` prefix | `Abstract_Command` |
| Boolean function | `Is_`/`Has_`/`Can_`/`Was_` | `Is_Valid` |

## Formatting

- **Indentation:** 3 spaces (no tabs)
- **Line width:** 120 characters maximum
- **Blank lines:** One between logical sections, two before each subprogram body

## String Types

Use standard Ada `String` type. All terminal capability strings (environment variable names, terminal identifiers, escape sequences) are pure ASCII.

## Package Header Template

```ada
-------------------------------------------------------------------------------
--  Package.Name - Short Description
--
--  Copyright (c) YYYY Termicap Contributors
--  SPDX-License-Identifier: Apache-2.0
-------------------------------------------------------------------------------

--  @summary
--  One-line summary.
--
--  @description
--  Detailed description.
--
--  Requirements Coverage:
--    - @relation(REQ-ID): Brief description
```

## Documentation

- Public subprograms: `@param`, `@return`, `@exception` tags
- `@relation(REQ-ID)` tag before each requirement-traced subprogram
- Section separators for grouping related declarations:
  ```ada
  ---------------------------------------------------------------------------
  --  Section Name (REQ-ID)
  ---------------------------------------------------------------------------
  ```

## SPARK Contracts

```ada
procedure Push (Item : Integer)
  with Pre  => not Is_Full,
       Post => Size = Size'Old + 1;
```

## Error Handling

- No exceptions in library code — use Result types
- Exceptions allowed in test code and top-level executables
