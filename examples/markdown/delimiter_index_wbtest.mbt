// Adversarial delimiter-index benchmarks.
//
// Each fixture prebuilds R distinct unmatched backtick-run lengths. The timed
// body measures only successor-index traversal, excluding lexing and parser
// context construction.

///|
fn benchmark_delimiter_index(b : @bench.T, run_count : Int) -> Unit {
  let starts : Array[Int] = []
  let lengths : Array[Int] = []
  for i in 0..<run_count {
    starts.push(i)
    lengths.push(i + 1)
  }
  b.bench(fn() {
    let index : CodeSpanDelimiterIndex = {
      eligible_openers: {},
      successors: {},
    }
    let previous_by_length : Map[Int, Int] = {}
    for i in 0..<run_count {
      index_code_span_delimiter_run(
        index,
        previous_by_length,
        starts[i],
        lengths[i],
        true,
      )
    }
    b.keep(index)
  })
}

///|
test "bench: code-span delimiter index R=512" (b : @bench.T) {
  benchmark_delimiter_index(b, 512)
}

///|
test "bench: code-span delimiter index R=1024" (b : @bench.T) {
  benchmark_delimiter_index(b, 1024)
}

///|
test "bench: code-span delimiter index R=2048" (b : @bench.T) {
  benchmark_delimiter_index(b, 2048)
}
