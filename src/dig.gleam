import gleam/dynamic.{type DecodeErrors, type Decoder, type Dynamic, DecodeError}
import gleam/list
import gleam/result.{replace_error, try}
import gleam/option.{type Option, None, Some}
import gleam/regex
import gleam/int
import gleam/iterator

pub type DigDecoder {
  DigObject(path: List(String), inner: Decoder(Dynamic))
  DigList(path: List(String), inner: Decoder(List(Dynamic)))
}

pub type DigError {
  ParsePath(inner: PathSegParseError)
}

pub type DigResult =
  Result(Option(DigDecoder), DigError)

pub fn dig(path: List(String)) -> DigResult {
  list.try_fold(path, None, fn(acc, it) {
    case acc {
      None -> {
        use it_dig_decoder <- try(dig_path_seg_with_path([], it))
        Ok(Some(it_dig_decoder))
      }
      Some(DigObject(acc_path, acc_decoder)) -> {
        use it_dig_decoder <- try(dig_path_seg_with_path(acc_path, it))

        let dig_decoder = case it_dig_decoder {
          DigObject(it_path, it_decoder) ->
            DigObject(it_path, fn(d) {
              use dd <- try(acc_decoder(d))
              it_decoder(dd)
              |> map_errors(fn(e) { DecodeError(..e, path: it_path) })
            })
          DigList(it_path, it_decoder) ->
            DigList(it_path, fn(d) {
              use dd <- try(acc_decoder(d))
              it_decoder(dd)
              |> map_errors(fn(e) { DecodeError(..e, path: it_path) })
            })
        }

        Ok(Some(dig_decoder))
      }
      Some(DigList(acc_path, acc_decoder)) -> {
        use it_dig_decoder <- try(dig_path_seg_with_path(acc_path, it))

        let dig_decoder = case it_dig_decoder {
          DigObject(it_path, it_decoder) ->
            DigList(it_path, fn(d) {
              use dd <- try(acc_decoder(d))
              iterator.from_list(dd)
              |> iterator.map(it_decoder)
              |> iterator.map(map_errors(_, fn(e) {
                DecodeError(..e, path: it_path)
              }))
              |> iterator.to_list()
              |> result.all()
            })
          DigList(it_path, it_decoder) ->
            DigList(it_path, fn(d) {
              use dd <- try(acc_decoder(d))
              list.flat_map(dd, fn(a) {
                // Result(List(D), E) -> List(Result(D,E))
                case it_decoder(a) {
                  Ok(aa) -> list.map(aa, Ok)
                  Error(e) -> [
                    map_errors(Error(e), fn(e) {
                      DecodeError(..e, path: it_path)
                    }),
                  ]
                }
              })
              |> result.all()
            })
        }

        Ok(Some(dig_decoder))
      }
    }
  })
}

pub fn dig_path_seg(path_seg: String) -> Result(DigDecoder, DigError) {
  dig_path_seg_with_path([], path_seg)
}

pub fn dig_path_seg_with_path(
  path: List(String),
  path_seg: String,
) -> Result(DigDecoder, DigError) {
  use parsed_path_seg <- try(
    parse_path_seg(path_seg)
    |> result.map_error(fn(e) { ParsePath(e) }),
  )

  let path = list.append(path, [path_seg])

  let decorder = case parsed_path_seg {
    Object(key) -> DigObject(path, dynamic.field(key, dynamic.dynamic))
    List(key_option, index_option) -> {
      case key_option, index_option {
        Some(key), None -> {
          DigList(path, dynamic.field(key, dynamic.list(dynamic.dynamic)))
        }
        None, None -> DigList(path, dynamic.list(dynamic.dynamic))
        Some(key), Some(index) ->
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
        None, Some(index) ->
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
    }
    Tuple(key_option, index) -> {
      case key_option {
        Some(key) ->
          DigObject(
            path,
            dynamic.field(key, dynamic.element(index, dynamic.dynamic)),
          )
        None -> DigObject(path, dynamic.element(index, dynamic.dynamic))
      }
    }
  }

  Ok(decorder)
}

pub type PathSeg {
  Object(key: String)
  List(key: Option(String), index: Option(Int))
  Tuple(key: Option(String), index: Int)
}

pub type PathSegParseError {
  InvalidPathSeg(path_seg: String)
}

pub type PathSegParseResult =
  Result(PathSeg, PathSegParseError)

pub fn parse_path_seg(path_seg: String) -> PathSegParseResult {
  parse_object_path_seg(path_seg)
  |> result.lazy_or(fn() { parse_list_path_seg(path_seg) })
  |> result.lazy_or(fn() { parse_tuple_path_seg(path_seg) })
}

pub fn parse_object_path_seg(path_seg: String) -> PathSegParseResult {
  let assert Ok(obj_regex) = regex.from_string("^\\w+$")
  case regex.scan(with: obj_regex, content: path_seg) {
    [] -> Error(InvalidPathSeg(path_seg))
    [first, ..] -> Ok(Object(first.content))
  }
}

pub fn parse_list_path_seg(path_seg: String) -> PathSegParseResult {
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
        Some(v) -> {
          use index <- try(
            int.parse(v)
            |> replace_error(InvalidPathSeg(path_seg)),
          )
          Ok(List(key, Some(index)))
        }
        None -> Ok(List(key, None))
      }
    }
  }
}

pub fn parse_tuple_path_seg(path_seg: String) -> PathSegParseResult {
  let assert Ok(tuple_regex) = regex.from_string("^(\\w*)\\((\\d+)\\)$")
  case regex.scan(with: tuple_regex, content: path_seg) {
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
        Some(v) -> {
          use index <- try(
            int.parse(v)
            |> replace_error(InvalidPathSeg(path_seg)),
          )
          Ok(Tuple(key, index))
        }
        None -> Error(InvalidPathSeg(path_seg))
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
