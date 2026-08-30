///|
/// A supplied change hint does not describe the authoritative updated source.
pub suberror MarkdownUpdateError {
  ChangeSetMismatch
} derive(Eq, Debug)

///|
/// Mutable owner of one Markdown source and its latest detached snapshot.
pub(all) struct IncrementalParser {
  priv source_id : @core.SourceId
  priv extensions : MarkdownExtensions
  priv mut source : String
  priv mut document : MarkdownDocument
}

///|
/// Create an incremental parser with a private parser lifetime.
pub fn IncrementalParser::IncrementalParser(
  source : String,
  source_id? : @core.SourceId = @core.SourceId("markdown"),
  extensions? : MarkdownExtensions = MarkdownExtensions::none(),
) -> IncrementalParser raise Failure {
  let document = parse(source, source_id~, extensions~)
  { source_id, extensions, source, document }
}

///|
/// Update from the authoritative source, optionally validating an old-to-new
/// change hint before parsing. State changes only after the new snapshot exists.
pub fn IncrementalParser::update(
  self : IncrementalParser,
  source : String,
  changes? : @text_change.ChangeSet,
) -> Unit raise {
  match changes {
    Some(changes) => {
      guard changes.apply(self.source) == Some(source) else {
        raise MarkdownUpdateError::ChangeSetMismatch
      }
    }
    None => ()
  }
  let document = parse(
    source,
    source_id=self.source_id,
    extensions=self.extensions,
  )
  self.source = source
  self.document = document
}

///|
/// Return the latest detached semantic snapshot.
pub fn IncrementalParser::snapshot(
  self : IncrementalParser,
) -> MarkdownDocument {
  self.document
}
