///|
test "literal fallback: unclosed bold delimiter" {
  inspect(
    parse(
      @core.SourceId("markdown-error-recovery-unclosed-bold"),
      "**unclosed\n",
    ),
    content="Document([Paragraph([Text(\"**unclosed\")])])",
  )
}

///|
test "error recovery: unclosed link" {
  inspect(
    parse(
      @core.SourceId("markdown-error-recovery-unclosed-link"),
      "[unclosed\n",
    ),
    content="Document([Paragraph([Error(\"[\"), Text(\"unclosed\")])])",
  )
}

///|
test "error recovery: unclosed code fence" {
  inspect(
    parse(
      @core.SourceId("markdown-error-recovery-unclosed-fence"),
      "```\ncode without close\n",
    ),
    content="Document([CodeBlock(\"\", \"code without close\")])",
  )
}

///|
test "error recovery: unmatched code-span run stays literal" {
  inspect(
    parse(
      @core.SourceId("markdown-error-recovery-unmatched-code-span"),
      "``unclosed *em*\n",
    ),
    content="Document([Paragraph([Text(\"``\"), Text(\"unclosed \"), Italic([Text(\"em\")])])])",
  )
}
