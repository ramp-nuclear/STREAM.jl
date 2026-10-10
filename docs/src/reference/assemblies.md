# Assemblies

```@autodocs
Modules = [STREAM.Assemblies, STREAM.Assemblies.Connect]
Private = false
```

## Composing and reaching ports

These are defined at the top level, since components use them too, and the `Assemblies`
module re-exports them.

```@autodocs
Modules = [STREAM]
Pages = ["assemblies/assembly.jl", "assemblies/port.jl"]
Private = false
```
