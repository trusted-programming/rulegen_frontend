include "rust.grm"

define LibcIntType
        libc :: c_char
    |   libc :: c_schar
    |   libc :: c_uchar
    |   libc :: c_short
    |   libc :: c_ushort
    |   libc :: c_int
    |   libc :: c_uint
    |   libc :: c_long
    |   libc :: c_ulong
    |   libc :: c_longlong
    |   libc :: c_ulonglong
end define

define LibcFloatType
    libc :: c_double
end define

define BuiltInUnsignedIntType
    u8 | u16 | u32 | u64 | u128
end define

define BuiltInSignedIntType
    i8 | i16 | i32 | i64 | i128
end define

define BuiltInFloatType
    f64
end define

define BuiltInIntType
        [BuiltInSignedIntType]
    |   [BuiltInUnsignedIntType]
end define

define IntType
        [LibcIntType]
    |   [BuiltInIntType]
end define

define FloatType
        [LibcFloatType]
    |   [BuiltInFloatType]
end define

redefine TypeNoBounds
        [IntType]
    |   [FloatType]
    |   [ParenthesizedType]
    |   [ImplTraitTypeOneBound]
    |   [TraitObjectTypeOneBound]
    |   [TypePath]
    |   [TupleType]
    |   [NeverType]
    |   [RawPointerType]
    |   [ReferenceType]
    |   [ArrayType]
    |   [SliceType]
    |   [InferredType]
    |   [QualifiedPathInType]
    |   [BareFunctionType]
    |   [MacroInvocation]
end redefine

define PubTypeAlias
    'pub [TypeAlias]
end define

redefine VisItem
        [PubTypeAlias] [NL]
    |   [Visibility?] [VisibleItem] [NL]
end redefine

%include "common.txl"

define iu_table_entry
    [BuiltInSignedIntType] '-> [BuiltInUnsignedIntType]
end define

define iustr_table_entry
    [stringlit] '-> [stringlit]
end define

define libc_to_basic_type_entry
    [TypeNoBounds] '-> [TypeNoBounds]
end define

% used to save all resolved type alias to built-in type mapping
% so in bitfield macro we know how to replace 'ty' field
define type_alias_TokenTree_table_entry
    [TokenTree*] '-> [TokenTree*]
end define

function main
    replace [program]
        P [program]
    export IU_Table [iu_table_entry*]
        i8 -> u8
        i16 -> u16
        i32 -> u32
        i64 -> u64
        i128 -> u128
    export IUSTR_Table [iustr_table_entry*]
        "i8" -> "u8"
        "i16" -> "u16"
        "i32" -> "u32"
        "i64" -> "u64"
        "i128" -> "u128"
    export LIBC_TO_BASIC_TYPE_Table [libc_to_basic_type_entry*]
        libc :: c_char -> i8
        libc :: c_schar -> i8
        libc :: c_uchar -> u8
        libc :: c_short -> i16
        libc :: c_ushort -> u16
        libc :: c_int -> i32
        libc :: c_uint -> u32
        libc :: c_long -> i64
        libc :: c_ulong -> u64
        libc :: c_longlong -> i64
        libc :: c_ulonglong -> u64
        libc :: c_double -> f64
    export TYPE_ALIAS_TOKENTREE_Table [type_alias_TokenTree_table_entry*]
        _
    by
        P   [libCInt2BuiltInInt]
            [libCFloat2BuiltInFloat]
            [resolveTypeAliases]
            [bitfield]
            [simplifyChainAsCasts]
            [simplifyIntLitCastToNumbersForWrappingTraits]
            [negativeInt2CustomType]
            [leftShiftOutOfRange]
            [rmLitIntAsCast]
            [cleanAsTypeNoBoudsForLocalVars]
            [simplifyLitIntGroupExpn]
            [negativeInt2UInt]
            [groupedNegativeInt2UInt]
end function

% SCRust bitfield macros uses `uint8_t` by default:
%   #[bitfield (name = "service", ty = "uint8_t", bits = "1..=1")]
% we need to update it to be `u8` instead
rule bitfield
    replace [TokenTree*]
        ty = TokenTree [TokenTree]
        Tail [TokenTree*]
    import TYPE_ALIAS_TOKENTREE_Table [type_alias_TokenTree_table_entry*]
    deconstruct * [type_alias_TokenTree_table_entry] TYPE_ALIAS_TOKENTREE_Table
        TokenTree -> IntTypeTokenTree [TokenTree*]
    by
        ty = IntTypeTokenTree
        [. Tail]
end rule

function _bitfield
    replace [program]
        P [program]
    by
        P   [_bitfield_uint8_t]
            [_bitfield_byte]
            [_bitfield_word16]
            [_bitfield_word32]
end function

rule _bitfield_uint8_t
    replace [TokenTree*]
        ty = "uint8_t"
        Tail [TokenTree*]
    by
        ty = "u8"
        Tail
end rule

rule _bitfield_byte
    replace [TokenTree*]
        ty = "byte"
        Tail [TokenTree*]
    by
        ty = "u8"
        Tail
end rule

rule _bitfield_word16
    replace [TokenTree*]
        ty = "word16"
        Tail [TokenTree*]
    by
        ty = "u16"
        Tail
end rule

rule _bitfield_word32
    replace [TokenTree*]
        ty = "word32"
        Tail [TokenTree*]
    by
        ty = "u32"
        Tail
end rule

rule libCInt2BuiltInInt
    replace [IntType]
        libc_type [LibcIntType]
    import LIBC_TO_BASIC_TYPE_Table [libc_to_basic_type_entry*]
    deconstruct * [libc_to_basic_type_entry] LIBC_TO_BASIC_TYPE_Table
        libc_type -> BuiltInIntType [BuiltInIntType]
    by
        BuiltInIntType
end rule

rule libCFloat2BuiltInFloat
    replace [FloatType]
        libc_type [LibcFloatType]
    import LIBC_TO_BASIC_TYPE_Table [libc_to_basic_type_entry*]
    deconstruct * [libc_to_basic_type_entry] LIBC_TO_BASIC_TYPE_Table
        libc_type -> BuiltInFloatType [BuiltInFloatType]
    by
        BuiltInFloatType
end rule

% remove redundant `as` cast for variables, e.g.:
% let mut pass : i32 = 0;
% pass = 0 as i32;
% to -->
% let mut pass : i32 = 0;
% pass = 0;
rule cleanAsTypeNoBoudsForLocalVars
    replace $ [Statement*]
        outers [OuterAttribute*]
        'let pattern [Pattern] type [COLON_Type?] equals_value [EQUALS_Expression?] ';
        scope [Statement*]
    deconstruct * [PathInExpression] pattern
        var_name [PathInExpression]
    deconstruct * [TypeNoBounds] type
        var_type [TypeNoBounds]
    by
        outers
        'let pattern type equals_value ';
        scope [rmAsTypeNoBoundsInExpression var_name var_type]
end rule

rule rmAsTypeNoBoundsInExpression var_name [PathInExpression] var_type [TypeNoBounds]
    replace [Expression]
        prefix_expns [Prefix_Expressions*]
        var_name 'as var_type
        infix_postfix_expns [Infix_Postfix_Expressions*]
    by
        prefix_expns
        var_name
        infix_postfix_expns
end rule

rule simplifyIntLitCastToNumbersForWrappingTraits
    replace $ [Expression]
        Prefix_Expressions [Prefix_Expressions*] ( Expn [Expression] )
        Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    where
        Infix_Postfix_Expressions [_hasId 'wrapping_add] [_hasId 'wrapping_mul] [_hasId 'wrapping_sub] [_hasId 'wrapping_div]
    by
        Prefix_Expressions ( Expn [_forceIntLitType] ) Infix_Postfix_Expressions
end rule

%   -(1 as i32) as VOID
% to
%   -(1i32) as VOID
rule negativeInt2CustomType
    replace $ [Expression]
        Prefix_Expressions [Prefix_Expressions*] ExpressionWithoutBlock [ExpressionWithoutBlock]
        'as TypeNoBounds [TypeNoBounds]
        Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    deconstruct not TypeNoBounds
        _ [IntType]
    by
        Prefix_Expressions ExpressionWithoutBlock [_forceIntLitType] 'as TypeNoBounds Infix_Postfix_Expressions
end rule

%   -(1 as u64 << 60) as u32
% to
%   -(1u64 << 60) as u32
rule leftShiftOutOfRange
    replace $ [Expression]
        Prefix_Expressions [Prefix_Expressions*] ExpressionWithoutBlock [ExpressionWithoutBlock]
        'as TypeNoBounds [TypeNoBounds]
        Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    deconstruct * [ArithmeticOrLogicalOperator] ExpressionWithoutBlock
        _ [ArithmeticOrLogicalOperator]
    by
        Prefix_Expressions ExpressionWithoutBlock [_forceIntLitType] 'as TypeNoBounds Infix_Postfix_Expressions
end rule

function _forceIntLitType
    replace * [Expression]
        IntLit [INTEGER_LITERAL] 'as BuiltInIntType [BuiltInIntType]
    construct IntLitStr [stringlit]
        _ [unparse IntLit]
    construct BuiltInIntTypeStr [stringlit]
        _ [unparse BuiltInIntType]
    construct IntLitWithTypeStr [stringlit]
        IntLitStr [+ BuiltInIntTypeStr]
    construct IntLitWithType [INTEGER_LITERAL]
        IntLit [parse IntLitWithTypeStr]
    by
        IntLitWithType
end function

rule simplifyChainAsCasts
    replace [Infix_Postfix_Expressions*]
        'as _ [IntType]
        'as TypeNoBounds [IntType]
        MoreInfix_Postfix_Expressions [Infix_Postfix_Expressions*]
    by
        'as TypeNoBounds
        MoreInfix_Postfix_Expressions
end rule

rule rmLitIntAsCast
    replace [Expression]
        IntLit [INTEGER_LITERAL] 'as _ [IntType]
        Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    by
        IntLit Infix_Postfix_Expressions
end rule

rule simplifyLitIntGroupExpn
    replace [OuterExpressionWithoutBlock]
        ( IntLit [INTEGER_LITERAL] )
    by
        IntLit
end rule

rule negativeInt2UInt
    replace [Expression]
        - LitInt [INTEGER_LITERAL] as BuiltInUnsignedIntType [BuiltInUnsignedIntType]
            Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    import IU_Table [iu_table_entry*]
    deconstruct * [iu_table_entry] IU_Table
        BuiltInSignedIntType [BuiltInSignedIntType] -> BuiltInUnsignedIntType
    by
        ( - LitInt ) as BuiltInSignedIntType as BuiltInUnsignedIntType
            Infix_Postfix_Expressions
end rule

rule groupedNegativeInt2UInt
    replace [Expression]
        ( - LitInt [INTEGER_LITERAL] ) as BuiltInUnsignedIntType [BuiltInUnsignedIntType]
            Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    import IU_Table [iu_table_entry*]
    deconstruct * [iu_table_entry] IU_Table
        BuiltInSignedIntType [BuiltInSignedIntType] -> BuiltInUnsignedIntType
    by
        ( - LitInt ) as BuiltInSignedIntType as BuiltInUnsignedIntType
            Infix_Postfix_Expressions
end rule

rule resolveTypeAliases
    replace [program]
        P [program]
    construct PubTypeAliases [PubTypeAlias*]
        _ [^ P] [_onlyWithIntType]
    construct Length [number]
        _ [length PubTypeAliases]
    where
        Length [> 0]
    by
        P [_resolveOneTypeAlias each PubTypeAliases]
end rule

rule _onlyWithIntType
    replace [PubTypeAlias*]
        Head [PubTypeAlias]
        Tail [PubTypeAlias*]
    deconstruct not Head
        pub 'type _ [id] = IntType [IntType] ;
    by
        Tail
end rule

function _resolveOneTypeAlias PubTypeAlias [PubTypeAlias]
    deconstruct PubTypeAlias
        pub 'type Id [id] = IntType [IntType] ;
    construct TypeNoBounds [TypeNoBounds]
        Id
    import TYPE_ALIAS_TOKENTREE_Table [type_alias_TokenTree_table_entry*]
    construct IntTypeStr [stringlit]
        _ [unparse IntType]
    construct TypeNoBoundsStr [stringlit]
        _ [unparse TypeNoBounds]
    construct IntTypeTokenTree [TokenTree*]
        _ [reparse IntTypeStr]
    construct TypeNoBoundsTokenTree [TokenTree*]
        _ [reparse TypeNoBoundsStr]
    construct NewEntry [type_alias_TokenTree_table_entry]
        TypeNoBoundsTokenTree -> IntTypeTokenTree
    export TYPE_ALIAS_TOKENTREE_Table
        NewEntry
        TYPE_ALIAS_TOKENTREE_Table
    replace [program]
        P [program]
    by
        P [_removeTypeAlias PubTypeAlias] [_replaceTypeNoBounds TypeNoBounds IntType]
end function

rule _replaceTypeNoBounds TypeNoBounds [TypeNoBounds] IntType [IntType]
    replace [TypeNoBounds]
        TypeNoBounds
    by
        IntType
end rule

rule _removeTypeAlias PubTypeAliasToDel [PubTypeAlias]
    replace [Item*]
        Head [Item]
        Items [Item*]
    deconstruct Head
        PubTypeAliasToDel
    by
        Items
end rule


% common.txl starts here
#if not TXL_RULES_COMMON then
#define TXL_RULES_COMMON

% remove all `as` cast of given type from scope
rule rmAsTypeNoBounds type_no_bounds [TypeNoBounds]
    replace [Infix_Postfix_Expressions*]
        head [Infix_Postfix_Expressions]
        tail [Infix_Postfix_Expressions*]
    deconstruct head
        'as type_no_bounds
    by
        tail
end rule

% prepend an Item in program, e.g.: adding "use std :: env ;"
function prependItemInProgram AnItem [Item]
    replace [program]
        Utf8Bom [UTF8BOM_NL?]
        Shebang [SHEBANG_NL?]
        InnerAttributes [InnerAttribute*]
        Items [Item*]
    deconstruct not * [Item] Items
        AnItem
    construct AllItems [Item*]
        AnItem Items
    by
        Utf8Bom
        Shebang
        InnerAttributes
        AllItems
end function

function prependItemInProgram2 AnItem [Item?] Msg [stringlit]
    replace [program]
        Utf8Bom [UTF8BOM_NL?]
        Shebang [SHEBANG_NL?]
        InnerAttributes [InnerAttribute*]
        Items [Item*]
    deconstruct AnItem
        Item [Item]
    deconstruct not * [Item] Items
        Item
    construct AllItems [Item*]
        Item Items [message Msg]
    by
        Utf8Bom
        Shebang
        InnerAttributes
        AllItems
end function

function seqContainItem AnItem [Item]
    match * [Item]
        AnItem
end function

% whether function is declared in an external block
function hasExternalFuncDecl FuncName [id]
    match * [ExternalFunctionItem]
        fn FuncName _ [Generics?] ( _ [NamedFunctionParameters_or_NamedFunctionParametersWithVariadics?] )
            _ [FunctionReturnType?] _ [WhereClause?]
            _ [SEMI_or_BlockExpression]
end function

function hasFuncDecl FuncName [id]
    match * [Function]
        _ [FunctionQualifiers] fn FuncName _ [Generics?] ( _ [FunctionParameters?] )
            _ [FunctionReturnType?] _ [WhereClause?]
            _ [SEMI_or_BlockExpression]
end function

function hasFuncCall FuncId [id]
    replace * [Expression]
        Expn [Expression]
    deconstruct Expn
        FuncId InfixPostFixExpns [Infix_Postfix_Expressions*]
    deconstruct InfixPostFixExpns
        ( _ [CallParams?] )
        _ [Infix_Postfix_Expressions*]
    by
        Expn
end function

function hasFuncCallInMacro FuncId [id]
    replace * [DelimTokenTree]
        DTT [DelimTokenTree]
    deconstruct * [id] DTT
        FuncId
    %where
    %    DTT [containId FuncId]
    by
        DTT [message FuncId]
end function

function containId Id [id]
    match * [id]
        Id
end function

rule rmExtFunc FuncId [id]
    replace [ExternalItem*]
        head [ExternalItem]
        tail [ExternalItem*]
    deconstruct head
        _ [OuterAttribute*]
        fn FuncId _ [Generics?] ( _ [NamedFunctionParameters_or_NamedFunctionParametersWithVariadics?] )
            _ [FunctionReturnType?] _ [WhereClause?]
            _ [SEMI_or_BlockExpression]
    by
        tail
end rule

rule rmFunc FuncId [id]
    replace [Item*]
        head [Item]
        tail [Item*]
    deconstruct head
        _ [OuterAttribute*]
        _ [FunctionQualifiers] fn FuncId _ [Generics?] ( _ [FunctionParameters?] )
            _ [FunctionReturnType?] _ [WhereClause?]
            _ [SEMI_or_BlockExpression]
    by
        tail
end rule

% rm function declarations in extern block that are not called.
function cleanExtFuncDecl FuncName [stringlit]
    construct FuncId [id]
        _ [+ FuncName]
    replace [Item*]
        Items [Item*]
    deconstruct * [ExternalFunctionItem] Items
        fn FuncId _ [Generics?] ( _ [NamedFunctionParameters_or_NamedFunctionParametersWithVariadics?] )
            _ [FunctionReturnType?] _ [WhereClause?]
            _ [SEMI_or_BlockExpression]
    deconstruct not * [Expression] Items
       FuncId _ [Postfix_CallExpression]
    % make sure the id is not used, e.g.: wolfssl-4.5.0/rust_rs2rs/src/wolfcrypt/test/test.rs:
    % pub const test_pass : unsafe extern "C" fn (_ : * const i8, _ :...) -> i32 = printf;
    deconstruct not * [ConstantItem] Items
        'const _ [IDENTIFIER_or_UNDERSCORE] ': _ [Type] '= FuncId ';
    where not
        Items [?hasFuncCallInMacro FuncId] %[?hasFuncCall FuncId]
    by
        Items [rmExtFunc FuncId]
end function

function cleanFunc FuncName [stringlit]
    construct FuncId [id]
        _ [+ FuncName]
    replace [Item*]
        Items [Item*]
    deconstruct * [Function] Items
        _ [FunctionQualifiers] fn FuncId _ [Generics?] ( _ [FunctionParameters?] )
            _ [FunctionReturnType?] _ [WhereClause?]
            _ [SEMI_or_BlockExpression]
    %where
    %    Items [hasFuncDecl FuncId]
    deconstruct not * [Expression] Items
       FuncId _ [Postfix_CallExpression]
    where not
        Items [?hasFuncCallInMacro FuncId] %[?hasFuncCall FuncId]
    by
        Items [rmFunc FuncId]
end function

function countIdInItems Items [Item*] Id [id]
    replace [number]
        N [number]
    construct AllIds [id*]
        _ [^ Items] [_filterIdSeq Id]
    by
        _ [length AllIds]
end function

rule _filterIdSeq Id [id]
    replace [id*]
        head [id]
        tail [id*]
    deconstruct not head
        Id
    %where
    %    Id [~= head]
    by
        tail
end rule

% remove given Item if given N is one
rule rmItemN N [number] ItemToRm [Item?] Msg [stringlit]
    deconstruct N
        1   % when N < 1, the item is not present
            % when N > 1, the item is declared & used
    deconstruct ItemToRm
        Item [Item]
    replace [Item*]
        Item
        Tail [Item*]
    by
        Tail [message Msg]
end rule

% add Id to UniqIds if it is in Ids and not in UniqIds
function _uniqIds Ids [id*] Id [id]
    replace [id*]
        UniqIds [id*]
    deconstruct * [id] Ids
        Id
    deconstruct not * [id] UniqIds
        Id
    by
        Id UniqIds
end function

function _hasId Id [id]
    match * [id]
        Id
end function

function _IdsHasId Id [id]
    match [id*]
        Ids [id*]
    deconstruct * [id] Ids
        Id
end function

function _StatementHasId Id [id]
    match [Statement]
        Statement [Statement]
    deconstruct * [id] Statement
        Id
end function

function _StatementsHasId Id [id]
    match [Statement*]
        Statements [Statement*]
    deconstruct * [id] Statements
        Id
end function

function _isLitExpnInteger
    match [LiteralExpression]
        _ [integer_number]
end function

function _isLitExpnFloat
    match [LiteralExpression]
        _ [float_number]
end function

function _isLibcCChar
    match [TypeNoBounds]
        libc::c_char
end function

function _isLibcCShort
    match [TypeNoBounds]
        libc::c_short
end function

function _isLibcCInt
    match [TypeNoBounds]
        libc::c_int
end function

function _isLibcCLong
    match [TypeNoBounds]
        libc::c_long
end function

function _isLibcCLongLong
    match [TypeNoBounds]
        libc::c_longlong
end function

function _isLibcCUShort
    match [TypeNoBounds]
        libc::c_ushort
end function

function _isLibcCUInt
    match [TypeNoBounds]
        libc::c_uint
end function

function _isLibcCULong
    match [TypeNoBounds]
        libc::c_ulong
end function

function _isLibcCULongLong
    match [TypeNoBounds]
        libc::c_ulonglong
end function

function _isU8
    match [TypeNoBounds]
        u8
end function

function _isU16
    match [TypeNoBounds]
        u16
end function

function _isU32
    match [TypeNoBounds]
        u32
end function

function _isU64
    match [TypeNoBounds]
        u64
end function

function _isI8
    match [TypeNoBounds]
        i8
end function

function _isI16
    match [TypeNoBounds]
        i16
end function

function _isI32
    match [TypeNoBounds]
        i32
end function

function _isI64
    match [TypeNoBounds]
        i64
end function

function _isLibcFloat
    match [TypeNoBounds]
        libc::c_float
end function

function _isLibcDouble
    match [TypeNoBounds]
        libc::c_double
end function

function _isF32
    match [TypeNoBounds]
        f32
end function

function _isF64
    match [TypeNoBounds]
        f64
end function

rule rmAnyAsTypeNoBounds
    replace [Infix_Postfix_Expressions*]
        'as _ [TypeNoBounds]
        tail [Infix_Postfix_Expressions*]
    by
        tail
end rule

rule rmLiteralAsTypeNoBounds
    replace [Expression]
        lit_expn [LiteralExpression] 'as type [TypeNoBounds] restInfixPostFixExpns [Infix_Postfix_Expressions*]
    where not
        lit_expn [isIntLitAsRawPtr type] [isByteStrLitAsRawPtr type]
    deconstruct not type
        _ [IDENTIFIER]
    by
        lit_expn restInfixPostFixExpns
end rule

rule rmStrLitAsTypeNoBounds
    replace [Expression]
        lit_expn [stringlit] 'as type [TypeNoBounds] restInfixPostFixExpns [Infix_Postfix_Expressions*]
    deconstruct not type
        _ [IDENTIFIER]
    by
        lit_expn restInfixPostFixExpns
end rule

% this is to avoid removing casts from integer to raw pointers, e.g. in 100_prisoners:
%   pub static mut drawerSet : * mut drawer = 0 as * const drawer as * mut drawer;
function isIntLitAsRawPtr type [TypeNoBounds]
    match [LiteralExpression]
        _ [INTEGER_LITERAL]
    deconstruct type
        _ [RawPointerType]
end function

% this is to avoid removing casts from BYTE_STRING_LITERAL to raw pointers, e.g. in array_length:
%   let mut fruit : [* const i8; 2] = [b"apples\x00" as *const i8, b"oranges\x00" as *const i8];
function isByteStrLitAsRawPtr type [TypeNoBounds]
    match [LiteralExpression]
        _ [BYTE_STRING_LITERAL]
    deconstruct type
        _ [RawPointerType]
end function

rule _castLitChar
    replace [Infix_ComparisonExpression]
        OP [ComparisonOperator] C [charlit]
    by
        OP C as i32
end rule

#end if

% common.txl ends here