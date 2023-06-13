
include "rust.grm"

%include "common.txl"

function main
    replace [program]
        P [program]
    by
        P   [cleanFnReturnAsTypeNoBouds]
            [castFnLiteralArgs P]
            [castReturnNull]
end function

rule cleanFnReturnAsTypeNoBouds
    replace $ [Function]
        qualifiers [FunctionQualifiers] 'fn ident [IDENTIFIER] generics [Generics?]
        '( pars [FunctionParameters?] ')
            '-> return_type [TypeNoBounds] where_clause [WhereClause?]
        body [SEMI_or_BlockExpression]   % observed - JRC
    deconstruct not return_type
        _ [TypePathSegment]
    by
        qualifiers 'fn ident generics
        '( pars ')
            '-> return_type where_clause
        body [_cleanReturnAsTypeNoBouds return_type]
end rule

rule _cleanReturnAsTypeNoBouds type [TypeNoBounds]
    replace $ [Expression]
        'return expn [Expression]
    deconstruct expn
        LiteralExpression [LiteralExpression] 'as type
    deconstruct not LiteralExpression
        _ [CHAR_LITERAL]
    deconstruct not * type
        _ [RawPointerType]
    by
        'return LiteralExpression
end rule

% some LiteralExpression casts need to be preserved, e.g.:
% fn x(f64 f); x(5 as f64);
% this rule should be called after [rmLiteralAsTypeNoBounds], which
% removes all literal casts, and before [stdio2Rust], which will
% transform printf (among others) to print! macro, which has TokenTree
% as its argument and is hard to do anthing in TXL
rule castFnLiteralArgs P [program]
    replace $ [Expression]
        FnId [id] ( CallParams [CallParam,+] _ [', ?] )
    construct ArgTypes [TypeNoBounds*]
        _ [_fnArgTypes FnId P]
    construct ArgTypesLength [number]
        _ [length ArgTypes]
    construct CallParamsLength [number]
        _ [length CallParams]
    deconstruct ArgTypesLength
        CallParamsLength
    %construct ArgIndice [number*]
    %    _ [_callParamIdxList each CallParams]
    construct CastedCallParams [CallParam,]
        _ [_castArg each CallParams ArgTypes]
    by
        FnId ( CastedCallParams )
end rule

% C code might "return NULL", but in Rust this has to be casted.
% And unfortunately we discarded this cast in some previous processing
rule castReturnNull
    replace $ [Function]
        FunctionQualifiers [FunctionQualifiers] 'fn IDENTIFIER [IDENTIFIER] Generics [Generics?]
        '( FunctionParameters [FunctionParameters?] ')
        '-> Type [TypeNoBounds] WhereClause [WhereClause?]
        SEMI_or_BlockExpression [SEMI_or_BlockExpression]
    by
        FunctionQualifiers 'fn IDENTIFIER Generics
        '( FunctionParameters ')
        '-> Type WhereClause
        SEMI_or_BlockExpression [_castReturnNull Type]
end rule

rule _castReturnNull Type [TypeNoBounds]
    replace [ReturnExpression]
        return NULL
    by
        return NULL 'as Type
end rule

function _callParamIdxList CallParam [CallParam]
    replace [number*]
        Numbers [number*]
    construct Length [number]
        _ [length Numbers]
    construct NewNumber [number]
        Length [+ 1]
    by
        Numbers [. NewNumber]
end function

function _fnArgTypes FnId [id] P [program]
    replace [TypeNoBounds*]
        _ [TypeNoBounds*]
    deconstruct * [Function] P
        _ [FunctionQualifiers] 'fn FnId _ [Generics?] '( FuncParams [FunctionParam,+] _ [', ?] ')
        _ [FunctionReturnType?] _ [WhereClause?]
        _ [SEMI_or_BlockExpression]
    construct FuncParamTypes [TypeNoBounds*]
        _ [_fnFuncParamType each FuncParams]
    by
        FuncParamTypes
end function

function _fnFuncParamType FuncParam [FunctionParam]
    replace [TypeNoBounds*]
        Types [TypeNoBounds*]
    deconstruct FuncParam
        _ [OuterAttribute*] _ [Pattern] ': Type [TypeNoBounds]
    by
        Types [. Type]
end function

function _castArg CallParam [CallParam] Type [TypeNoBounds]
    replace [CallParam,]
        CallParams [CallParam,]
    construct CastedCallParam [CallParam]
        CallParam [_castOneArg Type]
    by
        CallParams [, CastedCallParam]
end function

function _castOneArg Type [TypeNoBounds]
    replace [CallParam]
        CallParam [CallParam]
    deconstruct CallParam
        _ [LiteralExpression]
    by
        CallParam [_castAsInteger Type] [_castAsFloat Type]
end function

function _castAsInteger Type [TypeNoBounds]
    replace [CallParam]
        CallParam [CallParam]
    deconstruct CallParam
        LitExpn [LiteralExpression]
    where
        Type [_isLibcCChar] [_isLibcCInt] [_isLibcCLong]
            [_isU8] [_isU16] [_isU32] [_isU64]
            [_isI8] [_isI16] [_isI32] [_isI64]
    deconstruct not LitExpn
        _ [integer_number]
    by
        LitExpn as Type
end function

function _castAsFloat Type [TypeNoBounds]
    replace [CallParam]
        CallParam [CallParam]
    deconstruct CallParam
        LitExpn [LiteralExpression]
    where
        Type [_isLibcFloat] [_isLibcDouble]
            [_isF32] [_isF64]
    deconstruct not LitExpn
        _ [float_number]
    by
        LitExpn as Type
end function

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