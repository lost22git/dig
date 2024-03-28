# dig

Parse path expression as [dynamic.Decoder](https://hexdocs.pm/gleam_stdlib/gleam/dynamic.html#Decoder)

## Usage

```gleam
import gleeunit
import gleeunit/should
import dig
import gleam/option.{None, Some}
import gleam/json
import gleam/dynamic
import gleam/string
import gleam/list
import gleam/io

pub fn dig_test() {
  let json_str =
    "
  {
    \"foo\": [
      {
        \"bar\": [
          {
            \"baz\": \"a\"
          },
          {
            \"baz\": \"b\"
          }
        ]
      },
      {
        \"bar\": [
           {
            \"baz\": \"c\"
          },
          {
            \"baz\": \"d\"
          }
        ]
      }
    ],
    \"haha\": {
      \"meme\": 1
    }
  }
  "

  {
    let assert Ok(dig.DigObject(path, decoder)) =
      dig.dig(
        "foo[1].bar[1].baz"
        |> string.split("."),
      )

    should.equal(path, ["foo[1]", "bar[1]", "baz"])

    let assert Ok(d) =
      json_str
      |> json.decode(decoder)

    d
    |> dynamic.string()
    |> should.equal(Ok("d"))
  }

  {
    let assert Ok(dig.DigList(path, decoder)) =
      dig.dig(
        "foo[].bar[1].baz"
        |> string.split("."),
      )

    should.equal(path, ["foo[]", "bar[1]", "baz"])

    let assert Ok(d) =
      json_str
      |> json.decode(decoder)

    d
    |> list.map(dynamic.string)
    |> should.equal([Ok("b"), Ok("d")])
  }

  {
    let assert Ok(dig.DigList(path, decoder)) =
      dig.dig(
        "foo[].miss_me[1].baz"
        |> string.split("."),
      )

    should.equal(path, ["foo[]", "miss_me[1]", "baz"])

    let r =
      json_str
      |> json.decode(decoder)

    case r {
      Ok(_) -> should.fail()
      Error(errors) -> {
        io.debug(errors)
        Nil
      }
    }
  }
}
```


## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
gleam shell # Run an Erlang shell
```
