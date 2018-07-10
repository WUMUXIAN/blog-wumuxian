---
title: Gotchas for 'Methods' in Go
date: 2018-07-10 14:56:58
tags: Go
category: Go
---

Go is not strictly an object-oriented programming language, however it does have some features that enables you to use it in an object-oriented way, one of them is `Method`. Similar to some object-oriented programming language, where you define "Methods" for your object to specify the behaviours, properties and expose them to external users, in Go you can define functions for any of your types as well, and they are called "Methods" to that type.

We can define methods for a customized structure type:

```go
type Person struct {
	height, weight float64
}

func (o *Person) GetHeight() float64 {
	return o.height
}

func (o *Person) GetWeight() float64 {
	return o.weight
}

func (o *Person) GetBMI() float64 {
	return o.height / o.weight
}
```

We can also define methods for built-in primitive types:

```go
type Length int

func (o Length) Print() {
  fmt.Println(o)
}

type Values []float64

func (o *Values) Average() float64 {
	if len(o) == 0 {
		return float64(0)
	}
	average := float64(0)
	for _, v := range o {
		average += v
	}
	return average / float64(len(o))
}
```

As we can see above, a method definition always starts from a parameter with the given type or a pointer of that type, this indicates that this method is for that particular type, and this parameter is called `method receiver` in Go, it's a best practice to keep this consistent across all methods for this type.

> Gotcha 1: Always use the same parameter name for the `method receiver` across all methods to keep it consistent.

When I first came to Go, I always had questions regarding the method declaration.

- when should `method receiver` be the name type and when should it be an pointer of the type.
- what are differences between these two ways of declarations.
- can a variable of type T call a method whose receiver is a pointer.
- can a pointer variable of type T, a.k.a \*T, call a method whose receiver is a variable of type T.

```go
type Person struct {
	height, weight float64
}

// Method receiver is variable of Person
func (o Person) GetHeight() float64 {
	return o.height
}

// Method receiver is pointer of type Person
func (o *Person) GetWeight() float64 {
	return o.weight
}

// What are the differences and when to use which one?
```

First of all, whether to define your receiver as name types or pointers to them, it depends on your requirements. Calling a function makes a copy of each argument value (remember Go is pass-by-value) and the same applies to methods. As a result, if the method needs to update the value of the receiver, or if the receiver is too large to be copied, we must pass the address of the receiver using a pointer.

> Gotcha 2: When defining a method, if you need to update the value of the `receiver`, or the receiver is so large so that you want to avoid copying it, use `Pointer` of the `receiver` in the declaration.

Having said the above, can both types of declarations co-exist? The answer is a obvious yes, however, the best practice is that if you have one method with pointer receiver, then you should define all of your methods with pointer receiver.

> Gotcha 3: If one of your method uses pointer receiver, then define all others with pointer receivers as well.

To answer the last two questions, let's do an a little experiment, first of all, let's define a type and two methods.

```go
type Music struct{}

func (o *Music) Play() {
	fmt.Println("Music Playing")
}

func (o Music) Stop() {
	fmt.Println("Music Stopped")
}
```

Test 1:
```go
// Test 1
func main() {
	m := Music{}
	m.Play()
	m.Stop()
}

output:
Music Playing
Music Stopped
```

Test 2
```go
func main() {
	Music{}.Play()
	Music{}.Stop()
}

compilation error:
cannot call pointer method on Music literal
cannot take the address of Music literal
```

Test 3
```go
func main() {
	musics := map[string]Music{
		"music1": Music{},
		"music2": Music{},
	}
	musics["music1"].Play()
	musics["music1"].Stop()
}

compilation error:
cannot call pointer method on musics["music1"]
cannot take the address of musics["music1"]
```

Test 4
```go
func main() {
	m := &Music{}
	m.Play()
	m.Stop()
}

output:
Music Playing
Music Stopped
```

Test 5
```go
func main() {
	musics := map[string]*Music{
		"music1": &Music{},
		"music2": &Music{},
	}
	musics["music1"].Play()
	musics["music1"].Stop()
}

output:
Music Playing
Music Stopped
```

The experiment shows that it's ok to call a method whose `receiver` is a variable of the type, if the argument itself is a pointer, as reflected in `Test 4`, this is because the compiler implicitly dereferences the receiver, in other words, loads the value of the receiver from the address.

> Gotcha 4: If the `receiver` of a method is value type T, it's ok to call this method on pointer argument \*T, because compiler implicitly loads the value of the receiver from the address the pointer points to.
```
given:
var t \*T
func (o T) Method(){}

t.Method() is ok
```

However it's not always ok to call a method whose `receiver` is pointer type when the argument to call the method is value type, as reflected in `Test 2` and `Test 3`. The only ok case is `Test 1`, where the variable of T is addressable, this is because the compiler implicitly takes the address of the variable. In `Test 2` and `Test 3`, the compiler complains because the variable are not addressable.

> Gotcha 5: If the `receiver` of a method is point type \*T, it's **only** ok to call this method on argument T, when T is addressable, because compiler implicitly gets the address of T. When T is not addressable, compiler will complain.
```
given:
var t T
var tMap map[string]T
func (o *T) Method(){}

t.Method() is ok
T{}.Method() is not ok
tMap["key"].Method() is not ok
```

Due to the nature of Go's pass-by-value, there is on more important thing to take note. That is if all the methods of a named type T have a receiver type of T itself (not \*T), it is safe to copy instances of that type; calling any of its methods necessarily makes a copy. For example, time.Duration values are liberally copied, including as arguments to functions. But if any method has a pointer receiver, you should avoid copying instances of T because doing so may violate internal invariants. For example, copy ing an instance of bytes.Buffer would cause the original and the copy to alias the same underlying array of bytes. Subsequent method calls would have unpredictable effects.

> Gotcha 6: It's not safe to copy instances of a named type T, if T has methods that have pointer receivers as it will have unpredictable effects because the original and the copy will be pointing to the same underlying data.

### Conclusion

`Methods` are one of the key feature for object-oriented style of programming, in this article we introduced 6 Gotchas regarding the `Methods` of Go for named types which will be very helpful for new Go programmers. If you are new to Go, you might feel some of them strange, however once you get used to it, you'll find it quite nature and easy to understand.
