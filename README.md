# inon
Data serialization format in Zig

- Simple human-readable data serialization format
- Expression evaluation capabilties
- Operates on Zig's standard types
- Fast serialization and deserialization

# Example file
```
first_name = "joe";
last_name = "something";
age = 30;
address = {
    street_no = 420;
    city = "nyc";
};
phone_nos = [100, 200, 300];
```

See [``demo.zig``](demo.zig) file for integration example.

# License
This library is licensed under MIT License.  
See [LICENSE](LICENSE) for more info.
