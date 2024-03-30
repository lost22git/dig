import gleam/dynamic.{type DecodeErrors, type Decoder, type Dynamic, DecodeError}
import gleam/list
import gleam/result.{replace_error, try}
import gleam/option.{type Option, None, Some}
import gleam/regex
import gleam/int
import gleam/iterator

/// wrap `dynamic.Decoder` with a path
///
pub type DigDecoder {
  DigObject(path: List(String), inner: Decoder(Dynamic))
  DigList(path: List(String), inner: Decoder(List(Dynamic)))
}

/// get path of `DigDecoder`
///
pub fn get_path(dig_decoder: DigDecoder) -> List(String) {
  case dig_decoder {
    DigObject(path, _) -> path
    DigList(path, _) -> path
  }
}

pub type DigError {
  EmptyPath
  ParsePath(inner: PathSegParseError)
}

/// `Ok(DigDecoder)` or `Error(DigError)`
///
pub type DigResult =
  Result(DigDecoder, DigError)

/// dig `dynamic.Encoder` in path
///
pub fn dig(path: List(String)) -> DigResult {
  case path {
    [] -> Error(EmptyPath)

    [first, ..rest] -> {
      use first_dig_decoder <- try(dig_path_seg_with_path([], first))
      rest
      |> list.try_fold(first_dig_decoder, fn(acc_dig_decoder, it) {
        use it_dig_decoder <- try(dig_path_seg_with_path(
          get_path(acc_dig_decoder),
          it,
        ))
        acc_dig_decoder
        |> compose(it_dig_decoder)
        |> Ok()
      })
    }
  }
}

/// dig `dynamic.Decoder` in single path segment
///
pub fn dig_path_seg(path_seg: String) -> DigResult {
  dig_path_seg_with_path([], path_seg)
}

/// compose two `DigDecoder`s
pub fn compose(a: DigDecoder, b: DigDecoder) -> DigDecoder {
  case a, b {
    DigObject(_a_path, a_decoder), DigObject(b_path, b_decoder) ->
      DigObject(b_path, fn(d) {
        use dd <- try(a_decoder(d))
        b_decoder(dd)
        |> map_errors(fn(e) { DecodeError(..e, path: b_path) })
      })

    DigObject(_a_path, a_decoder), DigList(b_path, b_decoder) ->
      DigList(b_path, fn(d) {
        use dd <- try(a_decoder(d))
        b_decoder(dd)
        |> map_errors(fn(e) { DecodeError(..e, path: b_path) })
      })

    DigList(_a_path, a_decoder), DigObject(b_path, b_decoder) ->
      DigList(b_path, fn(d) {
        use dd <- try(a_decoder(d))
        iterator.from_list(dd)
        |> iterator.map(b_decoder)
        |> iterator.map(map_errors(_, fn(e) { DecodeError(..e, path: b_path) }))
        |> iterator.to_list()
        |> result.all()
      })

    DigList(_a_path, a_decoder), DigList(b_path, b_decoder) ->
      DigList(b_path, fn(d) {
        use dd <- try(a_decoder(d))
        {
          use ddd <- list.flat_map(dd)
          // Result(List(D), E) -> List(Result(D,E))
          case b_decoder(ddd) {
            Ok(v) -> list.map(v, Ok)
            Error(e) -> [
              map_errors(Error(e), fn(e) { DecodeError(..e, path: b_path) }),
            ]
          }
        }
        |> result.all()
      })
  }
}

fn dig_path_seg_with_path(
  path: List(String),
  path_seg: String,
) -> Result(DigDecoder, DigError) {
  use parsed_path_seg <- try(
    parse_path_seg(path_seg)
    |> result.map_error(fn(e) { ParsePath(e) }),
  )

  let path = list.append(path, [path_seg])

  case parsed_path_seg {
    // Object
    Object(key) -> DigObject(path, dynamic.field(key, dynamic.dynamic))

    // List
    List(Some(key), None) ->
      DigList(path, dynamic.field(key, dynamic.list(dynamic.dynamic)))

    // List
    List(None, None) -> DigList(path, dynamic.list(dynamic.dynamic))

    // List
    List(Some(key), Some(index)) ->
      DigObject(
        path,
        dynamic.field(key, fn(d) {
          use shadow_list <- try(
            dynamic.shallow_list(d)
            |> map_errors(fn(e) { DecodeError(..e, path: path) }),
          )
          shadow_list
          |> list.at(index)
          |> replace_error([
            DecodeError(
              expected: "index: " <> int.to_string(index),
              found: "missing",
              path: path,
            ),
          ])
        }),
      )

    // List
    List(None, Some(index)) ->
      DigObject(path, fn(d) {
        use shallow_list <- try(
          dynamic.shallow_list(d)
          |> map_errors(fn(e) { DecodeError(..e, path: path) }),
        )
        shallow_list
        |> list.at(index)
        |> replace_error([
          DecodeError(
            expected: "index: " <> int.to_string(index),
            found: "missing",
            path: path,
          ),
        ])
      })
  }
  |> Ok()
}

//  ------ PathSeg -------------------------

pub type PathSeg {
  Object(key: String)
  List(key: Option(String), index: Option(Int))
}

pub type PathSegParseError {
  InvalidPathSeg(path_seg: String)
}

pub type PathSegParseResult =
  Result(PathSeg, PathSegParseError)

/// parse single path segment
///
pub fn parse_path_seg(path_seg: String) -> PathSegParseResult {
  parse_object_path_seg(path_seg)
  |> result.lazy_or(fn() { parse_list_path_seg(path_seg) })
}

fn parse_object_path_seg(path_seg: String) -> PathSegParseResult {
  let assert Ok(obj_regex) = regex.from_string("^\\w+$")

  case regex.scan(with: obj_regex, content: path_seg) {
    [] -> Error(InvalidPathSeg(path_seg))
    [first, ..] -> Ok(Object(first.content))
  }
}

fn parse_list_path_seg(path_seg: String) -> PathSegParseResult {
  let assert Ok(list_regex) = regex.from_string("^(\\w*)\\[(\\d*)\\]$")
  case regex.scan(with: list_regex, content: path_seg) {
    [] -> Error(InvalidPathSeg(path_seg))

    [first, ..] -> {
      use key <- try(
        first.submatches
        |> list.first
        |> replace_error(InvalidPathSeg(path_seg)),
      )
      use index_option <- try(
        first.submatches
        |> list.at(1)
        |> replace_error(InvalidPathSeg(path_seg)),
      )

      case index_option {
        None -> Ok(List(key, None))
        Some(v) -> {
          use index <- try(
            int.parse(v)
            |> replace_error(InvalidPathSeg(path_seg)),
          )
          Ok(List(key, Some(index)))
        }
      }
    }
  }
}

fn map_errors(
  result: Result(t, DecodeErrors),
  f: fn(dynamic.DecodeError) -> dynamic.DecodeError,
) -> Result(t, DecodeErrors) {
  result.map_error(result, list.map(_, f))
}
