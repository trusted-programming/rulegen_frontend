#if not TXL_RULES_MAIN then
#define TXL_RULES_MAIN

include "rust.grm"

function main
    replace [program]
        P [program]
    by
        P   [castLiteralExpressions]
            %[convertArgcArgv]
            [random2Rust]
            [usleep2Rust]
            [exit2Rust]
            [cleanOuterAttributes]
            [rmUnstableInnerAttributes]
            [cleanExternCBlock]
            [rmUseScrust]
end function

function convertArgcArgv
    replace [program]
        P [program]
    construct UseEnvArg [Item]
        use std :: env ;
    by
        P [prependItemInProgram UseEnvArg] [convertFuncArgcArgv]
end function

#end if
% argcArgv.txl starts here

#if not TXL_RULES_ARGC_ARGV then
#define TXL_RULES_ARGC_ARGV

rule convertFuncArgcArgv
    replace [Function]
        FuncQualifiers [FunctionQualifiers] 'fn FuncName [IDENTIFIER] Generics [Generics?]
            '( mut argc : argcType [Type], mut argv : * mut * mut i8 ')
            FuncReturnType [FunctionReturnType?] WhereClause [WhereClause?]
            FuncBody [SEMI_or_BlockExpression]
    by
        FuncQualifiers 'fn FuncName Generics
            '( ')
            FuncReturnType WhereClause
            FuncBody [prependArgcArgv] [convertAtoi] [convertArgvOffset]
end rule

function prependArgcArgv
    replace [SEMI_or_BlockExpression]
        LoopLabel [LoopLabel?]
        '{
            InnerAttributes [InnerAttribute*]
            Statements [Statement*]
        '}
    construct ArgvStatement [Statement]
        let argv: Vec<String> = env::args().collect();
    construct ArgcStatement [Statement]
        let argc: usize = argv.len();
    where not
        Statements [seqContainStatement ArgvStatement]
    where not
        Statements [seqContainStatement ArgcStatement]
    construct AllStatements [Statement*]
        _ [. ArgvStatement] [. ArgcStatement] [. Statements]
    by
        LoopLabel
        '{
            InnerAttributes
            AllStatements
        '}
end function

function seqContainStatement Statement [Statement]
    match * [Statement]
        Statement
end function

rule convertAtoi
    replace [Expression]
        atoi (* argv.offset ( Expn [Expression]))
    by
        argv'[ Expn '] .parse() .unwrap()
end rule

rule convertArgvOffset
    replace [Expression]
        * argv.offset (Expn [Expression])
    by
        argv '[ Expn ']
end rule

#end if

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

% common.txl ends here
#end if

% exit.txl starts here
#if not TXL_RULES_EXIT then
#define TXL_RULES_EXIT

% transform C exit(int) function call to Rust ::std::process::exit
function exit2Rust
    replace [program]
        P [program]
    construct UseProcExit [Item?]
        _ [_getUseProcExit]
    by
        P   [prependItemInProgram2 UseProcExit ""]
            [simplifyRustExitCall]
            [cleanUpExit]
end function

function _getUseProcExit
    replace [Item?]
        _ [Item?]
    construct UseProcExit [Item]
        use std::process::exit;
    by
        UseProcExit
end function

rule simplifyRustExitCall
    replace [PathExpression]
        :: std :: process :: exit
    by
        exit
end rule

function cleanUpExit
    replace [program]
        utf8bom [UTF8BOM_NL?]
        shebang [SHEBANG_NL?]
        inner_attrs[InnerAttribute*]
        items [Item*]
    construct Id [id]
        exit
    construct NExit [number]
        _ [countIdInItems items Id]
    construct UseProcExit [Item?]
        _ [_getUseProcExit]
    by
        utf8bom
        shebang
        inner_attrs
        items   [rmExtFunc Id]
                [rmItemN NExit UseProcExit ""]
end function

% exit.txl ends here
#end if

% externCBlock.txl starts here
#if not TXL_RULES_EXTERN_C_BLOCK then
#define TXL_RULES_EXTERN_C_BLOCK

function cleanExternCBlock
    replace [program]
        utf8bom [UTF8BOM_NL?]
        shebang [SHEBANG_NL?]
        inner_attrs[InnerAttribute*]
        items [Item*]
    by
        utf8bom
        shebang
        inner_attrs
        items   [rmEmptyExternCBlock]
end function

rule rmEmptyExternCBlock
    replace [Item*]
        head [Item]
        tail [Item*]
    deconstruct head
        'extern "C" '{ '}
    by
        tail
end rule

% externCBlock.txl ends here
#end if

% innerAttributes.txl starts here
#if not TXL_RULES_INNER_ATTRIBUTES then
#define TXL_RULES_INNER_ATTRIBUTES

% remove all unstable inner attributes
rule rmUnstableInnerAttributes
    replace [InnerAttribute*]
        head [InnerAttribute]
        tail [InnerAttribute*]
    deconstruct head
        _ [SHEBANG] '[ name [IDENTIFIER] _ [AttrInput?] ']
    construct ids_to_clean [IDENTIFIER*]
        feature register_tool
    where name [= each ids_to_clean]
    by
        tail
end rule

% innerAttributes.txl ends here 
#end if

% outerAttributes.txl starts here
#if not TXL_RULES_OUTER_ATTRIBUTES then
#define TXL_RULES_OUTER_ATTRIBUTES

% remove all unstable outer attributes
rule cleanOuterAttributes
    replace [OuterAttribute*]
        head [OuterAttribute]
        tail [OuterAttribute*]
    deconstruct head
        '# '[ main ']
    by
        tail
end rule

% outerAttributes.txl ends here
#end if

% primitiveTypes.txl starts here
#if not TXL_RULES_PRIMITIVE_TYPES then
#define TXL_RULES_PRIMITIVE_TYPES

function castLiteralExpressions
    replace [program]
        P [program]
    by
        P [castStaticItem]
end function

rule castStaticItem
    replace [StaticItem]
        'static Mut ['mut ?] ID [IDENTIFIER] ': Type [TypeNoBounds] '= c [charlit] ';
    where not
        Type [_isLibcCChar]
    by
        static Mut ID : Type = c as Type ;
end rule

% primitiveTypes.txl ends here
#end if

% random.txl starts here
#if not TXL_RULES_RANDOM then
#define TXL_RULES_RANDOM

% transform C srand() function call to Rust Pcg64::seed_from_u64()
function random2Rust
    replace [program]
        P [program]
    construct UseRandPrelude [Item?]
        _ [_getUseRandPrelude]
    construct UseRandPcg [Item?]
        _ [_getUseRandPcg]
    construct UseLazyStatic [Item?]
        _ [_getUseLazyStatic]
    construct UseMutex [Item?]
        _ [_getUseMutex]
    construct StructRustRand [Item?]
        _ [_getStructRustRand]
    construct ImplRustRand [Item?]
        _ [_getImplRustRand]
    construct GlobalRustRand [Item?]
        _ [_getGlobalRustRand]
    by
        P   [prependItemInProgram2 GlobalRustRand ""]
            [prependItemInProgram2 ImplRustRand ""]
            [prependItemInProgram2 StructRustRand ""]
            [prependItemInProgram2 UseMutex ""]
            [prependItemInProgram2 UseLazyStatic "ADD_DEP (lazy_static, 1.4.0)"]
            [prependItemInProgram2 UseRandPcg "ADD_DEP (rand_pcg, 0.3.0)"]
            [prependItemInProgram2 UseRandPrelude "ADD_DEP (rand, 0.8.0)"]
            [convertSrand]
            [convertRand]
            [cleanUpRandom]
end function

function _getUseRandPcg
    replace [Item?]
        _ [Item?]
    construct UseRandPcg [Item]
        use rand_pcg::Pcg64;
    by
        UseRandPcg
end function

function _getUseRandPrelude
    replace [Item?]
        _ [Item?]
    construct UseRandPrelude [Item]
        use rand::prelude::*;
    by
        UseRandPrelude
end function

function _getUseLazyStatic
    replace [Item?]
        _ [Item?]
    construct UseLazyStatic [Item]
        use lazy_static::lazy_static;
    by
        UseLazyStatic
end function

function _getUseMutex
    replace [Item?]
        _ [Item?]
    construct UseMutex [Item]
        use std::sync::Mutex;
    by
        UseMutex
end function

function _getStructRustRand
    replace [Item?]
        _ [Item?]
    construct StructRustRand [Item]
        struct RustRand {
            rng: Option<Pcg64>,
        }
    by
        StructRustRand
end function

function _getImplRustRand
    replace [Item?]
        _ [Item?]
    construct ImplRustRand [Item]
        impl RustRand {
            fn srand(&mut self, seed: u64) {
                self.rng = Some(Pcg64::seed_from_u64(seed));
        }
            fn rand(&mut self) -> i32 {
                if ! self.rng.is_some() {
                    self.rng = Some(Pcg64::seed_from_u64( '0 ));
                }
                let result: i32 = 'match self.rng.iter_mut().next() {
                    Some(v) => v.gen(),
                    _ => '0
                };
                return result.abs();
            }
        }
    by
        ImplRustRand
end function

function _getGlobalRustRand
    replace [Item?]
        _ [Item?]
    construct GlobalRustRand [Item]
        lazy_static! {
            static ref RUST_RAND: Mutex<RustRand> = Mutex::new(RustRand {rng: None});
        }
    by
        GlobalRustRand
end function

rule convertSrand
    replace [Expression]
        srand ( CallParam [CallParams?] ) Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    construct CallParamStr [stringlit]
        _ [unparse CallParam]
    construct CallParamStrWithCast [stringlit]
        CallParamStr [+ " as u64"]
    construct CallParamWithCast [CallParams?]
        _ [parse CallParamStrWithCast]
    by
        RUST_RAND.lock().unwrap().srand( CallParamWithCast )
        Infix_Postfix_Expressions [_castLitChar]
end rule

% transform C rand() call
rule convertRand
    replace [Expression]
        rand Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    deconstruct Infix_Postfix_Expressions
        ( )
        tail [Infix_Postfix_Expressions*]
    by
        RUST_RAND.lock().unwrap().rand
        Infix_Postfix_Expressions
end rule

function cleanUpRandom
    replace [program]
        utf8bom [UTF8BOM_NL?]
        shebang [SHEBANG_NL?]
        inner_attrs[InnerAttribute*]
        items [Item*]
    construct Id [id]
        RUST_RAND
    construct NRustRand [number]
        _ [countIdInItems items Id]
    construct UseRandPcg [Item?]
        _ [_getUseRandPcg]
    construct UseRandPrelude [Item?]
        _ [_getUseRandPrelude]
    construct UseLazyStatic [Item?]
        _ [_getUseLazyStatic]
    construct UseMutex [Item?]
        _ [_getUseMutex]
    construct StructRustRand [Item?]
        _ [_getStructRustRand]
    construct ImplRustRand [Item?]
        _ [_getImplRustRand]
    construct GlobalRustRand [Item?]
        _ [_getGlobalRustRand]
    by
        utf8bom
        shebang
        inner_attrs
        items   [cleanExtFuncDecl "srand"]
                [cleanExtFuncDecl "rand"]
                [rmItemN NRustRand UseRandPrelude "DEL_DEP (rand, 0.8.0)"]
                [rmItemN NRustRand UseRandPcg "DEL_DEP (rand_pcg, 0.3.0)"]
                [rmItemN NRustRand UseLazyStatic "DEL_DEP (lazy_static, 1.4.0)"]
                [rmItemN NRustRand UseMutex ""]
                [rmItemN NRustRand StructRustRand ""]
                [rmItemN NRustRand ImplRustRand ""]
                [rmItemN NRustRand GlobalRustRand ""]
end function

% random.txl ends here
#end if

% scrust.txl starts here
#if not TXL_RULES_SCRUST then
#define TXL_RULES_SCRUST

% rules specific to scrust transpiled Rust
% remove uncompilable use for stable Ruse
rule rmUseScrust
    replace [Item*]
        use ::scrust::*;
        items [Item*]
    by
        items
end rule

% scrust.txl ends here
#end if

% usleep.txl starts here
#if not TXL_RULES_USLEEP then
#define TXL_RULES_USLEEP

% transform C usleep(useconds_t usec) function call to Rust thread::sleep(duration)

function usleep2Rust
    replace [program]
        P [program]
    construct UseTimeDuration [Item?]
        _ [_getUseTimeDuration]
    construct FuncRustSleep [Item?]
        _ [_getFuncRustSleep]
    by
        P   [prependItemInProgram2 FuncRustSleep ""]
            [prependItemInProgram2 UseTimeDuration ""]
            [convertSleep]
            [cleanUpSleep]
end function

function _getUseTimeDuration
    replace [Item?]
        _ [Item?]
    construct UseTimeDuration [Item]
        use std::{thread, time};
    by
        UseTimeDuration
end function

function _getFuncRustSleep
    replace [Item?]
        _ [Item?]
    construct FuncRustSleep [Item]
        pub fn rust_sleep_ms(msec:u64) {
            let sec_micros = time::Duration::from_micros(msec);
            thread::sleep(sec_micros);
        }
    by
        FuncRustSleep
end function

rule convertSleep
    replace [Expression]
        usleep ( CallParam [CallParams?] ) Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    deconstruct CallParam
        secs[INTEGER_LITERAL] _ [Infix_Postfix_Expressions*]
    by
        rust_sleep_ms(secs)
        Infix_Postfix_Expressions [_castLitChar]
end rule

function cleanUpSleep
    replace [program]
        utf8bom [UTF8BOM_NL?]
        shebang [SHEBANG_NL?]
        inner_attrs[InnerAttribute*]
        items [Item*]
    construct Id [id]
        rust_sleep_ms
    construct NRustSleep [number]
        _ [countIdInItems items Id]
    construct UseTimeDuration [Item?]
        _ [_getUseTimeDuration]
    construct FuncRustSleep [Item?]
        _ [_getFuncRustSleep]
    by
        utf8bom
        shebang
        inner_attrs
        items   [cleanExtFuncDecl "usleep"]
                [rmItemN NRustSleep UseTimeDuration ""]
                [rmItemN NRustSleep FuncRustSleep ""]
end function
% usleep.txl ends here

#end if

