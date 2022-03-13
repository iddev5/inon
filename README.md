# inon
Data configuration format in Zig

- Simple human-readable data serialization format
- Host function execution capabilties
- Operates on Zig's standard types
- Fast serialization and deserialization

# Example file
```
first_name: "joe"
last_name: "something"
age: 50
address: {
    street_no :: (= age 30) : 420
    street_no :: (= age 40) : 40
    street_no :: (= age 50) : 50
    street_no ?: 60
    num: * (self "street_no") 2
    city: "nyc"
}
phone_nos: [100, 200, 300]
second_no: index phone_nos 1
```

See [``demo.zig``](demo.zig) file for integration example.

# License
This library is licensed under MIT License.  
See [LICENSE](LICENSE) for more info.
