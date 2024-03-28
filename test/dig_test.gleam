import gleeunit
import gleeunit/should
import dig
import gleam/option.{None, Some}
import gleam/json
import gleam/dynamic
import gleam/string
import gleam/list
import gleam/io

pub fn main() {
  gleeunit.main()
}

pub fn parse_path_seg_test() {
  // Object
  {
    let assert Ok(dig.Object(key)) =
      "abc"
      |> dig.parse_path_seg()
    key
    |> should.equal("abc")
  }
  // List
  {
    let assert Ok(dig.List(Some(key), index)) =
      "abc[1]"
      |> dig.parse_path_seg()
    key
    |> should.equal("abc")
    index
    |> should.equal(Some(1))
  }
  {
    let assert Ok(dig.List(None, index)) =
      "[1]"
      |> dig.parse_path_seg()
    index
    |> should.equal(Some(1))
  }
  {
    let assert Ok(dig.List(None, index)) =
      "[]"
      |> dig.parse_path_seg()
    index
    |> should.equal(None)
  }
  // Tuple
  {
    let assert Ok(dig.Tuple(Some(key), index)) =
      "abc(1)"
      |> dig.parse_path_seg()
    key
    |> should.equal("abc")
    index
    |> should.equal(1)
  }
  {
    let assert Ok(dig.Tuple(None, index)) =
      "(1)"
      |> dig.parse_path_seg()
    index
    |> should.equal(1)
  }
}

pub fn dig_path_seg_test() {
  {
    let dig_decoder =
      "abc"
      |> dig.dig_path_seg()

    case dig_decoder {
      Ok(dig.DigObject(path, inner)) -> {
        should.equal(path, ["abc"])

        let assert Ok(d) =
          "{\"abc\": \"x\"}"
          |> json.decode(inner)

        let assert Ok(v) = dynamic.string(d)
        should.equal(v, "x")

        Nil
      }
      _ -> should.fail()
    }
  }

  {
    let dig_decoder =
      "abc[1]"
      |> dig.dig_path_seg()

    case dig_decoder {
      Ok(dig.DigObject(path, inner)) -> {
        should.equal(path, ["abc[1]"])

        let assert Ok(d) =
          "{\"abc\": [ \"x\",\"y\" ]}"
          |> json.decode(inner)

        let assert Ok(v) = dynamic.string(d)
        should.equal(v, "y")

        Nil
      }
      _ -> should.fail()
    }
  }
}

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
        "foo[].bar[].baz"
        |> string.split("."),
      )

    should.equal(path, ["foo[]", "bar[]", "baz"])

    let assert Ok(d) =
      json_str
      |> json.decode(decoder)

    d
    |> list.map(dynamic.string)
    |> should.equal([Ok("a"), Ok("b"), Ok("c"), Ok("d")])
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

  {
    let assert Ok(dig.DigObject(path, decoder)) =
      dig.dig(
        "haha.miss_me.baz"
        |> string.split("."),
      )

    should.equal(path, ["haha", "miss_me", "baz"])

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
