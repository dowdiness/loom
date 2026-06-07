///|
/// CST kind space for the MoonBit parser skeleton.
///
/// Official lexer token kinds mirror `@tokens.TokenKind`; synthetic
/// trivia/error/EOF kinds and coarse top-level item nodes are kept separate.
/// Raw values for the original skeleton nodes are preserved, while official
/// token raw values start at 100 in the `TokenKind` declaration order.
pub(all) enum MoonbitSyntaxKind {
  // Synthetic token kinds
  TriviaToken
  ErrorToken
  IncompleteToken
  EofToken
  // Official MoonBit lexer token kinds
  AmperToken
  AmperAmperToken
  AndToken
  AsToken
  AsyncToken
  AttributeToken
  AugmentedAssignmentToken
  BarToken
  BarBarToken
  BreakToken
  ByteToken
  BytesToken
  CaretToken
  CatchToken
  CharToken
  ColonToken
  ColonColonToken
  CommaToken
  CommentToken
  ConstToken
  ContinueToken
  DeclareToken
  DeferToken
  DeriveToken
  DotDotToken
  DotIntToken
  DotLidentToken
  DotLparenToken
  DotUidentToken
  DoubleToken
  EllipsisToken
  ElseToken
  EnumToken
  EnumviewToken
  EqualToken
  EqTildeToken
  ExclamationToken
  ExistsToken
  ExtenumToken
  ExternToken
  FalseToken
  FatArrowToken
  FloatToken
  FnToken
  FnaliasToken
  ForToken
  ForallToken
  GuardToken
  IfToken
  ImplToken
  ImpliesToken
  ImportToken
  InToken
  Infix1Token
  Infix2Token
  Infix3Token
  Infix4Token
  IntToken
  InterpToken
  IsToken
  LbraceToken
  LbracketToken
  LetToken
  LetrecToken
  LexmatchToken
  LexmatchQuestionToken
  LidentToken
  LoopToken
  LparenToken
  LtPlusToken
  MatchToken
  MinusToken
  MultilineInterpToken
  MultilineStringToken
  MutableToken
  NewlineToken
  NobreakToken
  NoraiseToken
  PackageToken
  PackageNameToken
  PipeToken
  PipeLeftToken
  PlusToken
  PlusEqualToken
  PostLabelToken
  PrivToken
  ProofAssertToken
  ProofLetToken
  PubToken
  QuestionToken
  RaiseToken
  RangeExclusiveToken
  RangeExclusiveRevToken
  RangeInclusiveToken
  RangeInclusiveRevToken
  RangeLtInclusiveToken
  RbraceToken
  RbracketToken
  ReadonlyToken
  RegexInterpToken
  RegexLiteralToken
  ReturnToken
  RparenToken
  SemiToken
  StringToken
  StructToken
  SuberrorToken
  TestToken
  ThinArrowToken
  ThrowToken
  TraitToken
  TraitaliasToken
  TrueToken
  TryToken
  TryExclamationToken
  TryQuestionToken
  TypeToken
  TypealiasToken
  UidentToken
  UnderscoreToken
  UsingToken
  WhereToken
  WhileToken
  WithToken
  // Node kinds
  SourceFileNode
  SourceItemNode
  LetItemNode
  FunctionItemNode
  StructItemNode
  EnumItemNode
  TypeItemNode
} derive(Eq, Debug)

///|
pub impl Show for MoonbitSyntaxKind with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl @seam.ToRawKind for MoonbitSyntaxKind with fn to_raw(self) {
  RawKind(
    match self {
      TriviaToken => 0
      ErrorToken => 7
      IncompleteToken => 8
      EofToken => 9
      AmperToken => 100
      AmperAmperToken => 101
      AndToken => 102
      AsToken => 103
      AsyncToken => 104
      AttributeToken => 105
      AugmentedAssignmentToken => 106
      BarToken => 107
      BarBarToken => 108
      BreakToken => 109
      ByteToken => 110
      BytesToken => 111
      CaretToken => 112
      CatchToken => 113
      CharToken => 114
      ColonToken => 115
      ColonColonToken => 116
      CommaToken => 117
      CommentToken => 118
      ConstToken => 119
      ContinueToken => 120
      DeclareToken => 121
      DeferToken => 122
      DeriveToken => 123
      DotDotToken => 124
      DotIntToken => 125
      DotLidentToken => 126
      DotLparenToken => 127
      DotUidentToken => 128
      DoubleToken => 129
      EllipsisToken => 130
      ElseToken => 131
      EnumToken => 132
      EnumviewToken => 133
      EqualToken => 134
      EqTildeToken => 135
      ExclamationToken => 136
      ExistsToken => 137
      ExtenumToken => 138
      ExternToken => 139
      FalseToken => 140
      FatArrowToken => 141
      FloatToken => 142
      FnToken => 143
      FnaliasToken => 144
      ForToken => 145
      ForallToken => 146
      GuardToken => 147
      IfToken => 148
      ImplToken => 149
      ImpliesToken => 150
      ImportToken => 151
      InToken => 152
      Infix1Token => 153
      Infix2Token => 154
      Infix3Token => 155
      Infix4Token => 156
      IntToken => 157
      InterpToken => 158
      IsToken => 159
      LbraceToken => 160
      LbracketToken => 161
      LetToken => 162
      LetrecToken => 163
      LexmatchToken => 164
      LexmatchQuestionToken => 165
      LidentToken => 166
      LoopToken => 167
      LparenToken => 168
      LtPlusToken => 169
      MatchToken => 170
      MinusToken => 171
      MultilineInterpToken => 172
      MultilineStringToken => 173
      MutableToken => 174
      NewlineToken => 175
      NobreakToken => 176
      NoraiseToken => 177
      PackageToken => 178
      PackageNameToken => 179
      PipeToken => 180
      PipeLeftToken => 181
      PlusToken => 182
      PlusEqualToken => 183
      PostLabelToken => 184
      PrivToken => 185
      ProofAssertToken => 186
      ProofLetToken => 187
      PubToken => 188
      QuestionToken => 189
      RaiseToken => 190
      RangeExclusiveToken => 191
      RangeExclusiveRevToken => 192
      RangeInclusiveToken => 193
      RangeInclusiveRevToken => 194
      RangeLtInclusiveToken => 195
      RbraceToken => 196
      RbracketToken => 197
      ReadonlyToken => 198
      RegexInterpToken => 199
      RegexLiteralToken => 200
      ReturnToken => 201
      RparenToken => 202
      SemiToken => 203
      StringToken => 204
      StructToken => 205
      SuberrorToken => 206
      TestToken => 207
      ThinArrowToken => 208
      ThrowToken => 209
      TraitToken => 210
      TraitaliasToken => 211
      TrueToken => 212
      TryToken => 213
      TryExclamationToken => 214
      TryQuestionToken => 215
      TypeToken => 216
      TypealiasToken => 217
      UidentToken => 218
      UnderscoreToken => 219
      UsingToken => 220
      WhereToken => 221
      WhileToken => 222
      WithToken => 223
      SourceFileNode => 10
      SourceItemNode => 11
      LetItemNode => 12
      FunctionItemNode => 13
      StructItemNode => 14
      EnumItemNode => 15
      TypeItemNode => 16
    },
  )
}

///|
pub impl @seam.FromRawKind for MoonbitSyntaxKind with fn from_raw(raw) {
  match raw.0 {
    0 => TriviaToken
    7 => ErrorToken
    8 => IncompleteToken
    9 => EofToken
    10 => SourceFileNode
    11 => SourceItemNode
    12 => LetItemNode
    13 => FunctionItemNode
    14 => StructItemNode
    15 => EnumItemNode
    16 => TypeItemNode
    100 => AmperToken
    101 => AmperAmperToken
    102 => AndToken
    103 => AsToken
    104 => AsyncToken
    105 => AttributeToken
    106 => AugmentedAssignmentToken
    107 => BarToken
    108 => BarBarToken
    109 => BreakToken
    110 => ByteToken
    111 => BytesToken
    112 => CaretToken
    113 => CatchToken
    114 => CharToken
    115 => ColonToken
    116 => ColonColonToken
    117 => CommaToken
    118 => CommentToken
    119 => ConstToken
    120 => ContinueToken
    121 => DeclareToken
    122 => DeferToken
    123 => DeriveToken
    124 => DotDotToken
    125 => DotIntToken
    126 => DotLidentToken
    127 => DotLparenToken
    128 => DotUidentToken
    129 => DoubleToken
    130 => EllipsisToken
    131 => ElseToken
    132 => EnumToken
    133 => EnumviewToken
    134 => EqualToken
    135 => EqTildeToken
    136 => ExclamationToken
    137 => ExistsToken
    138 => ExtenumToken
    139 => ExternToken
    140 => FalseToken
    141 => FatArrowToken
    142 => FloatToken
    143 => FnToken
    144 => FnaliasToken
    145 => ForToken
    146 => ForallToken
    147 => GuardToken
    148 => IfToken
    149 => ImplToken
    150 => ImpliesToken
    151 => ImportToken
    152 => InToken
    153 => Infix1Token
    154 => Infix2Token
    155 => Infix3Token
    156 => Infix4Token
    157 => IntToken
    158 => InterpToken
    159 => IsToken
    160 => LbraceToken
    161 => LbracketToken
    162 => LetToken
    163 => LetrecToken
    164 => LexmatchToken
    165 => LexmatchQuestionToken
    166 => LidentToken
    167 => LoopToken
    168 => LparenToken
    169 => LtPlusToken
    170 => MatchToken
    171 => MinusToken
    172 => MultilineInterpToken
    173 => MultilineStringToken
    174 => MutableToken
    175 => NewlineToken
    176 => NobreakToken
    177 => NoraiseToken
    178 => PackageToken
    179 => PackageNameToken
    180 => PipeToken
    181 => PipeLeftToken
    182 => PlusToken
    183 => PlusEqualToken
    184 => PostLabelToken
    185 => PrivToken
    186 => ProofAssertToken
    187 => ProofLetToken
    188 => PubToken
    189 => QuestionToken
    190 => RaiseToken
    191 => RangeExclusiveToken
    192 => RangeExclusiveRevToken
    193 => RangeInclusiveToken
    194 => RangeInclusiveRevToken
    195 => RangeLtInclusiveToken
    196 => RbraceToken
    197 => RbracketToken
    198 => ReadonlyToken
    199 => RegexInterpToken
    200 => RegexLiteralToken
    201 => ReturnToken
    202 => RparenToken
    203 => SemiToken
    204 => StringToken
    205 => StructToken
    206 => SuberrorToken
    207 => TestToken
    208 => ThinArrowToken
    209 => ThrowToken
    210 => TraitToken
    211 => TraitaliasToken
    212 => TrueToken
    213 => TryToken
    214 => TryExclamationToken
    215 => TryQuestionToken
    216 => TypeToken
    217 => TypealiasToken
    218 => UidentToken
    219 => UnderscoreToken
    220 => UsingToken
    221 => WhereToken
    222 => WhileToken
    223 => WithToken
    _ => ErrorToken
  }
}

///|
fn MoonbitSyntaxKind::from_token_kind(
  kind : @tokens.TokenKind,
) -> MoonbitSyntaxKind {
  match kind {
    TK_AMPER => AmperToken
    TK_AMPERAMPER => AmperAmperToken
    TK_AND => AndToken
    TK_AS => AsToken
    TK_ASYNC => AsyncToken
    TK_ATTRIBUTE => AttributeToken
    TK_AUGMENTED_ASSIGNMENT => AugmentedAssignmentToken
    TK_BAR => BarToken
    TK_BARBAR => BarBarToken
    TK_BREAK => BreakToken
    TK_BYTE => ByteToken
    TK_BYTES => BytesToken
    TK_CARET => CaretToken
    TK_CATCH => CatchToken
    TK_CHAR => CharToken
    TK_COLON => ColonToken
    TK_COLONCOLON => ColonColonToken
    TK_COMMA => CommaToken
    TK_COMMENT => CommentToken
    TK_CONST => ConstToken
    TK_CONTINUE => ContinueToken
    TK_DECLARE => DeclareToken
    TK_DEFER => DeferToken
    TK_DERIVE => DeriveToken
    TK_DOTDOT => DotDotToken
    TK_DOT_INT => DotIntToken
    TK_DOT_LIDENT => DotLidentToken
    TK_DOT_LPAREN => DotLparenToken
    TK_DOT_UIDENT => DotUidentToken
    TK_DOUBLE => DoubleToken
    TK_ELLIPSIS => EllipsisToken
    TK_ELSE => ElseToken
    TK_ENUM => EnumToken
    TK_ENUMVIEW => EnumviewToken
    TK_EOF => EofToken
    TK_EQUAL => EqualToken
    TK_EQ_TILDE => EqTildeToken
    TK_EXCLAMATION => ExclamationToken
    TK_EXISTS => ExistsToken
    TK_EXTENUM => ExtenumToken
    TK_EXTERN => ExternToken
    TK_FALSE => FalseToken
    TK_FAT_ARROW => FatArrowToken
    TK_FLOAT => FloatToken
    TK_FN => FnToken
    TK_FNALIAS => FnaliasToken
    TK_FOR => ForToken
    TK_FORALL => ForallToken
    TK_GUARD => GuardToken
    TK_IF => IfToken
    TK_IMPL => ImplToken
    TK_IMPLIES => ImpliesToken
    TK_IMPORT => ImportToken
    TK_IN => InToken
    TK_INFIX1 => Infix1Token
    TK_INFIX2 => Infix2Token
    TK_INFIX3 => Infix3Token
    TK_INFIX4 => Infix4Token
    TK_INT => IntToken
    TK_INTERP => InterpToken
    TK_IS => IsToken
    TK_LBRACE => LbraceToken
    TK_LBRACKET => LbracketToken
    TK_LET => LetToken
    TK_LETREC => LetrecToken
    TK_LEXMATCH => LexmatchToken
    TK_LEXMATCH_QUESTION => LexmatchQuestionToken
    TK_LIDENT => LidentToken
    TK_LOOP => LoopToken
    TK_LPAREN => LparenToken
    TK_LT_PLUS => LtPlusToken
    TK_MATCH => MatchToken
    TK_MINUS => MinusToken
    TK_MULTILINE_INTERP => MultilineInterpToken
    TK_MULTILINE_STRING => MultilineStringToken
    TK_MUTABLE => MutableToken
    TK_NEWLINE => NewlineToken
    TK_NOBREAK => NobreakToken
    TK_NORAISE => NoraiseToken
    TK_PACKAGE => PackageToken
    TK_PACKAGE_NAME => PackageNameToken
    TK_PIPE => PipeToken
    TK_PIPE_LEFT => PipeLeftToken
    TK_PLUS => PlusToken
    TK_PLUS_EQUAL => PlusEqualToken
    TK_POST_LABEL => PostLabelToken
    TK_PRIV => PrivToken
    TK_PROOF_ASSERT => ProofAssertToken
    TK_PROOF_LET => ProofLetToken
    TK_PUB => PubToken
    TK_QUESTION => QuestionToken
    TK_RAISE => RaiseToken
    TK_RANGE_EXCLUSIVE => RangeExclusiveToken
    TK_RANGE_EXCLUSIVE_REV => RangeExclusiveRevToken
    TK_RANGE_INCLUSIVE => RangeInclusiveToken
    TK_RANGE_INCLUSIVE_REV => RangeInclusiveRevToken
    TK_RANGE_LT_INCLUSIVE => RangeLtInclusiveToken
    TK_RBRACE => RbraceToken
    TK_RBRACKET => RbracketToken
    TK_READONLY => ReadonlyToken
    TK_REGEX_INTERP => RegexInterpToken
    TK_REGEX_LITERAL => RegexLiteralToken
    TK_RETURN => ReturnToken
    TK_RPAREN => RparenToken
    TK_SEMI => SemiToken
    TK_STRING => StringToken
    TK_STRUCT => StructToken
    TK_SUBERROR => SuberrorToken
    TK_TEST => TestToken
    TK_THIN_ARROW => ThinArrowToken
    TK_THROW => ThrowToken
    TK_TRAIT => TraitToken
    TK_TRAITALIAS => TraitaliasToken
    TK_TRUE => TrueToken
    TK_TRY => TryToken
    TK_TRY_EXCLAMATION => TryExclamationToken
    TK_TRY_QUESTION => TryQuestionToken
    TK_TYPE => TypeToken
    TK_TYPEALIAS => TypealiasToken
    TK_UIDENT => UidentToken
    TK_UNDERSCORE => UnderscoreToken
    TK_USING => UsingToken
    TK_WHERE => WhereToken
    TK_WHILE => WhileToken
    TK_WITH => WithToken
  }
}
