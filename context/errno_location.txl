include "rust.grm"

define CONST_IDENTIFIER_or_UNDERSCORE
    [IDENTIFIER_or_UNDERSCORE]
end define

redefine ConstantItem
    'const [CONST_IDENTIFIER_or_UNDERSCORE] ': [Type] '= [Expression] ';
end redefine

%include "common.txl"

function main
    replace [program]
        P   [program]
    by
        P   [errLocation]
end function

% case:
%   pub const errno: libc::c_int = *__errno_location();
%   error[E0015]: calls in constants are limited to
%       constant functions, tuple structs and tuple variants
% this is not valid Rust code as it tries to initiate a const var with non-const
% function call
function errLocation
    replace [program]
        P [program]
    construct ErrLocConstantItems [ConstantItem*]
        _ [^ P] [_only_errno_location]
    construct CONST_IDENTIFIER_or_UNDERSCOREs [CONST_IDENTIFIER_or_UNDERSCORE*]
        _ [^ ErrLocConstantItems]
    construct ErrLocVarIds [id*]
        _ [^ CONST_IDENTIFIER_or_UNDERSCOREs]
    by
        P   [__errno_location]
            [_replace_in_expression each ErrLocVarIds]
            [_replace_in_match_expression each ErrLocVarIds]
end function

rule _replace_in_expression Id [id]
    replace [Expression]
        Id Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    by
        * __errno_location () Infix_Postfix_Expressions
end rule

rule _replace_in_match_expression Id [id]
    replace [MatchExpression]
        'match Id
        '{
            InnerAttribute [InnerAttribute*]
            MatchArms [MatchArms?]
        '}
    by
        'match * __errno_location ()
        '{
            InnerAttribute
            MatchArms
        '}
end rule

rule _only_errno_location
    replace [ConstantItem*]
        ConstantItem [ConstantItem]
        Tail [ConstantItem*]
    deconstruct not ConstantItem
        'const _ [CONST_IDENTIFIER_or_UNDERSCORE] ': _ [Type]
            '= * __errno_location () ';
    by
        Tail
end rule

rule __errno_location
    replace [ConstantItem]
        'const IDENTIFIER_or_UNDERSCORE [CONST_IDENTIFIER_or_UNDERSCORE] ': Type [Type]
            '= * __errno_location () ';
    by
        'const IDENTIFIER_or_UNDERSCORE ': Type
            '= '0 ';
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