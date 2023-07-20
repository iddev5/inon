# inon
Data configuration format in Zig

- Simple human-readable data serialization format
- Function execution capabilties: both native as well as foreign
- Operates on Zig's standard types
- Fast, powerful serialization and deserialization
- Pretty printing and serialization to JSON capabilities

# Example file
```
first_name: "joe"
last_name: "some {first_name} thing"
age: 50
address: {
    street_no: switch %{
        (= age 30): 420
        (= age 40): 40
        (= age 50): 50
        else: 70
    }
    num: * (self "street_no") 2
    city: "nyc"
}
phone_nos: [100, 200, 300]
second_no: index phone_nos 1
```

See [``demo.zig``](demo.zig) file for integration example.
Use [``repl.zig``](repl.zig), using ``zig build run-repl`` for a REPL-environment.

# License
This library is licensed under MIT License.  
See [LICENSE](LICENSE) for more info.
