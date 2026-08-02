// Private reactive MarkdownIR shell.
//
// Local interpretation and reference resolution are keyed by structurally
// reusable CST nodes. Absolute placement and contextual recovery remain in the
// terminal document computation.

///|
priv struct ReactiveMarkdownDocumentRoot {
  cst : @seam.CstNode
  start : Int
} derive(Eq)

///|
priv struct ReactiveMarkdownBlockSlot {
  cst : @seam.CstNode
  start : Int
  document_child_index : Int
} derive(Eq)

///|
priv struct ReactiveMarkdownDocumentLayout {
  origin : MarkdownIROrigin
  blocks : Array[ReactiveMarkdownBlockSlot]
} derive(Eq)

///|
priv struct ReactiveKeyedMarkdownIRCounters {
  enabled : Bool
  mut local_lowering : Int
  mut label_projection : Int
  mut block_resolution : Int
  mut placement : Int
  mut contextual_fallback : Int
}

///|
#warnings("-unused_value")
priv struct ReactiveKeyedMarkdownIRCounterSnapshot {
  local_lowering : Int
  label_projection : Int
  block_resolution : Int
  placement : Int
  contextual_fallback : Int
} derive(Eq, Debug)

///|
priv struct ReactiveKeyedMarkdownIRMapSweep {
  before : Int
  removed : Int
  after : Int
} derive(Eq, Debug)

///|
#warnings("-unused_value")
priv struct ReactiveKeyedMarkdownIRCacheSweep {
  resolved : ReactiveKeyedMarkdownIRMapSweep
  plan : ReactiveKeyedMarkdownIRMapSweep
  definition : ReactiveKeyedMarkdownIRMapSweep
} derive(Eq, Debug)

///|
priv struct ReactiveKeyedMarkdownIR {
  scope : @incr.Scope
  runtime : @incr.Runtime
  plan_by_cst : @incr.DerivedMap[@seam.CstNode, LocalBlockPlan]
  definition_by_label : @incr.DerivedMap[String, LinkReferenceDefinition?]
  resolved_by_cst : @incr.DerivedMap[@seam.CstNode, ResolvedLocalBlock]
  watch : @incr.Watch[MarkdownIR]
  counters : ReactiveKeyedMarkdownIRCounters
}

///|
fn is_local_unresolved_flow_block(node : @seam.SyntaxNode) -> Bool {
  let kind : SyntaxKind = @seam.FromRawKind::from_raw(node.kind())
  match kind {
    HeadingNode
    | ParagraphNode
    | BlockQuoteNode
    | UnorderedListNode
    | OrderedListNode
    | CodeBlockNode
    | HtmlBlockNode
    | ThematicBreakNode
    | ErrorNode => true
    _ => false
  }
}

///|
fn reactive_markdown_document_root(
  syntax : @seam.SyntaxNode,
) -> ReactiveMarkdownDocumentRoot {
  let root = syntax_root(syntax)
  { cst: root.cst_node(), start: root.start() }
}

///|
fn reactive_markdown_syntax_root(
  root : ReactiveMarkdownDocumentRoot,
) -> @seam.SyntaxNode {
  @seam.SyntaxNode::from_cst(root.cst, offset=root.start)
}

///|
fn reactive_markdown_document_layout(
  root : ReactiveMarkdownDocumentRoot,
) -> ReactiveMarkdownDocumentLayout {
  let syntax = reactive_markdown_syntax_root(root)
  let blocks : Array[ReactiveMarkdownBlockSlot] = []
  for child_index, child in syntax.children() {
    if is_local_unresolved_flow_block(child) {
      blocks.push({
        cst: child.cst_node(),
        start: child.start(),
        document_child_index: child_index,
      })
    }
  }
  { origin: origin_from_node(syntax), blocks }
}

///|
#warnings("-unused_value")
fn attach_reactive_keyed_markdown_ir_with_counters(
  parser : @loom.SyntaxParser,
  counters_enabled : Bool,
) -> ReactiveKeyedMarkdownIR {
  let source_id = parser.source_id()
  let runtime = parser.runtime()
  let scope = @incr.Scope::new(runtime)
  let counters : ReactiveKeyedMarkdownIRCounters = {
    enabled: counters_enabled,
    local_lowering: 0,
    label_projection: 0,
    block_resolution: 0,
    placement: 0,
    contextual_fallback: 0,
  }
  let snapshot_view = parser.snapshot()
  let syntax_view = parser.syntax_tree()
  // Contextual recovery is a dynamic branch. Keep its coherent parser input
  // alive even while valid documents do not depend on it.
  ignore(scope.watch(snapshot_view))
  let document_root = scope.derived(
    () => reactive_markdown_document_root(syntax_view.get_or_abort()),
    label="markdown_ir_document_root",
  )
  let document_layout = scope.derived(
    () => reactive_markdown_document_layout(document_root.get_or_abort()),
    label="markdown_ir_document_layout",
  )
  let definition_index = scope.derived(
    () => {
      collect_link_reference_definitions(
        reactive_markdown_syntax_root(document_root.get_or_abort()),
      )
    },
    label="markdown_ir_definition_index",
  )
  let definition_by_label = scope.derived_map(
    label => {
      if counters.enabled {
        counters.label_projection += 1
      }
      definition_index.get_or_abort().lookup(label)
    },
    label="markdown_ir_definition_by_label",
  )
  let plan_by_cst = scope.derived_map(
    cst => {
      if counters.enabled {
        counters.local_lowering += 1
      }
      lower_local_unresolved_block(source_id, cst)
    },
    label="markdown_ir_local_plan_by_cst",
  )
  let resolved_by_cst = scope.derived_map(
    cst => {
      if counters.enabled {
        counters.block_resolution += 1
      }
      resolve_local_block(plan_by_cst.get_or_abort(cst), label => {
        definition_by_label.get_or_abort(label)
      })
    },
    label="markdown_ir_resolved_by_cst",
  )
  let document = scope.derived(
    () => {
      let layout = document_layout.get_or_abort()
      let children : Array[MarkdownIR] = []
      for slot in layout.blocks {
        let local_result = resolved_by_cst.get_or_abort(slot.cst)
        let resolved = if resolved_local_block_requires_context(local_result) {
          if counters.enabled {
            counters.contextual_fallback += 1
          }
          let snapshot = snapshot_view.get_or_abort()
          let current_root = reactive_markdown_syntax_root(
            reactive_markdown_document_root(snapshot.syntax),
          )
          let current_children = current_root.children()
          guard slot.document_child_index < current_children.length() else {
            abort("reactive MarkdownIR layout child index is stale")
          }
          let current_block = current_children[slot.document_child_index]
          guard current_block.cst_node() == slot.cst else {
            abort("reactive MarkdownIR layout child does not match its CST key")
          }
          lower_contextual_resolved_block(
            source_id,
            current_block,
            snapshot.source,
            label => definition_by_label.get_or_abort(label),
            origin => {
              diagnostics_in_origin(source_id, snapshot.diagnostics, origin)
            },
          )
        } else {
          local_result
        }
        if counters.enabled {
          counters.placement += 1
        }
        children.push(place_resolved_local_block(resolved, slot.start))
      }
      MarkdownIR::document(children, layout.origin)
    },
    label="markdown_ir_reactive_keyed_document",
  )
  let watch = scope.watch(document)
  {
    scope,
    runtime,
    plan_by_cst,
    definition_by_label,
    resolved_by_cst,
    watch,
    counters,
  }
}

///|
#warnings("-unused_value")
fn attach_reactive_keyed_markdown_ir(
  parser : @loom.SyntaxParser,
) -> ReactiveKeyedMarkdownIR {
  attach_reactive_keyed_markdown_ir_with_counters(parser, false)
}

///|
#warnings("-unused_value")
fn attach_instrumented_reactive_keyed_markdown_ir(
  parser : @loom.SyntaxParser,
) -> ReactiveKeyedMarkdownIR {
  attach_reactive_keyed_markdown_ir_with_counters(parser, true)
}

///|
#warnings("-unused_value")
fn ReactiveKeyedMarkdownIR::read(self : ReactiveKeyedMarkdownIR) -> MarkdownIR {
  self.watch.read_or_abort()
}

///|
#warnings("-unused_value")
fn ReactiveKeyedMarkdownIR::counter_snapshot(
  self : ReactiveKeyedMarkdownIR,
) -> ReactiveKeyedMarkdownIRCounterSnapshot {
  {
    local_lowering: self.counters.local_lowering,
    label_projection: self.counters.label_projection,
    block_resolution: self.counters.block_resolution,
    placement: self.counters.placement,
    contextual_fallback: self.counters.contextual_fallback,
  }
}

///|
#warnings("-unused_value")
fn ReactiveKeyedMarkdownIR::reset_counters(
  self : ReactiveKeyedMarkdownIR,
) -> Unit {
  self.counters.local_lowering = 0
  self.counters.label_projection = 0
  self.counters.block_resolution = 0
  self.counters.placement = 0
  self.counters.contextual_fallback = 0
}

///|
#warnings("-unused_value")
fn ReactiveKeyedMarkdownIR::collect_stale(
  self : ReactiveKeyedMarkdownIR,
) -> ReactiveKeyedMarkdownIRCacheSweep {
  ignore(self.watch.read_or_abort())
  let resolved_before = self.resolved_by_cst.cache_len()
  let plan_before = self.plan_by_cst.cache_len()
  let definition_before = self.definition_by_label.cache_len()
  self.runtime.gc()
  let resolved_removed = self.resolved_by_cst.sweep_cache()
  let plan_removed = self.plan_by_cst.sweep_cache()
  let definition_removed = self.definition_by_label.sweep_cache()
  {
    resolved: {
      before: resolved_before,
      removed: resolved_removed,
      after: self.resolved_by_cst.cache_len(),
    },
    plan: {
      before: plan_before,
      removed: plan_removed,
      after: self.plan_by_cst.cache_len(),
    },
    definition: {
      before: definition_before,
      removed: definition_removed,
      after: self.definition_by_label.cache_len(),
    },
  }
}

///|
#warnings("-unused_value")
fn ReactiveKeyedMarkdownIR::dispose(self : ReactiveKeyedMarkdownIR) -> Unit {
  self.scope.dispose()
}
