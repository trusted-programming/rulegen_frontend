include "rust.grm"

% Optimized rule guards, patterns and replacements - JC 17 Jan 2020
% Optimized using agile parsing refinements - JC 17 Jan 2020

define VariadicType
    '...     % observed - JRC
end define

define MutStaticIdentifier
    'mut [IDENTIFIER]
end define

define OptMutStaticIdentifier
    	[MutStaticIdentifier]
    |	[IDENTIFIER]
end define

redefine StaticItem
    'static [OptMutStaticIdentifier] ': [Type] '= [Expression] ';
end redefine

redefine ExternalStaticItem
    'static [OptMutStaticIdentifier] ': [Type] [EQUALS_Expression?] ';  [NL]
end redefine

redefine FunctionParam
        [OuterAttribute*] [FunctionParamPattern] ': [Type]
    |   [OuterAttribute*] [FunctionParamPattern] ': [VariadicType]
end redefine

define FunctionParamPattern
 	[Pattern]
end define

% Refine grammar to identify declared variables

redefine LetStatement
    [OuterAttribute*] 'let [LetPattern] [COLON_Type?] [EQUALS_Expression?] ';      [NL]
end redefine

define LetPattern
    [Pattern]
end define

% Refine grammar to identify external function identifiers
redefine ExternalFunctionItem
    'fn [ExternalFunctionIdentifier] [Generics?] '( [NamedFunctionParameters_or_NamedFunctionParametersWithVariadics?] ')
        [FunctionReturnType?] [WhereClause?]
    [SEMI_or_BlockExpression]   % observed - JRC
end redefine

define ExternalFunctionIdentifier
    [IDENTIFIER]
end define

redefine Function
        [UnsafeFunction]
    |   [SafeFunction]
end redefine

define UnsafeFunctionIdentifier
    [IDENTIFIER]
end define

define UnsafeFunction
    [AsyncConstQualifiers?] 'unsafe [EXTERN_Abi?] 'fn [UnsafeFunctionIdentifier] [Generics?] '( [FunctionParameters?] ')
        [FunctionReturnType?] [WhereClause?]
    [SEMI_or_BlockExpression]   % observed - JRC
end define

define SafeFunctionIdentifier
    [IDENTIFIER]
end define

define SafeFunction
    [AsyncConstQualifiers?] [EXTERN_Abi?] 'fn [SafeFunctionIdentifier] [Generics?] '( [FunctionParameters?] ')
        [FunctionReturnType?] [WhereClause?]
    [SEMI_or_BlockExpression]   % observed - JRC
end define

% Refine grammar to identify unsafe type def using BareFunctionType
define TypeAliasPattern
    'type [IDENTIFIER]
end define

redefine TypeAlias
    [TypeAliasPattern] [Generics?]
	[COLON_TypeParamBounds?] 	% observed - JRC
	[WhereClause?]
	[EQUALS_Type?] ';		% observed - JRC
end redefine

define MacroSimplePath
    [SimplePath]
end define

redefine MacroInvocationSemi
        [MacroSimplePath] [SPOFF] '! [SPON] '( [TokenTree*] ') [SEMI_or_EndOfBlock]  [NL]
    |   [MacroSimplePath] [SPOFF] '! [SPON] '[ [TokenTree*] '] [SEMI_or_EndOfBlock]  [NL]
    |   [MacroSimplePath] [SPOFF] '! [SPON] '{ [TokenTree*] '}
end redefine

%include "common.txl"

function main
    replace [program]
        P   [program]
    % pass one to get all non-external function signatures as
    % less unsafe as possible
    construct SaferP [program]
        P   [markAllFuncUnsafe]
            [sinkUnsafe]
    export Global_UnsafeSymbolIds [id*]
        _   [_getAllUnsafeSymbolIds SaferP]
    export Global_UnsafeTypeAliasIds [id*]
        _   [_getUnsafeTypeAliases SaferP]
    by
        % pass two to handle missed unsafe statements that calls
        % unsafe non-external functions
        SaferP  [cleanUnsafePerFunction]
                [concatenateUnsafeBlocks]
                [shiftStatementIntoUnsafeBlock]
                [rmEmptyUnsafeBlockExpression]
                [rmNestedUnsafe]
end function

rule rmNestedUnsafe
    replace $ [UnsafeBlockExpression]
        'unsafe '{
            InnerAttribute [InnerAttribute*]
            Statements [Statements]
        '}
    % to avoud when functions are defined inside an unafe block.
    % as such a function is not counted as unsafe for the compiler,
    % hence if the unsafe block nested is removed, then compiler
    % complains that unsafe operations are in safe function.
    % e.g. ptrdist-1.1/ft/rust_rs2rs/src/random.rs:
    % function random_0 inside srandom
    deconstruct not * [Function] Statements
        _ [Function]
    by
        'unsafe '{
            InnerAttribute
            Statements [_rmUnsafeBlockStatement]
        '}
end rule

rule _rmUnsafeBlockStatement
    replace [Statement*]
        'unsafe '{
            Statements [Statement*]
        '}
        Tail [Statement*]
    % to ensure after removing the blocks these statements end properly.
    % not that if the `return` value of such an block is used, then this
    % will break it!
    construct EmptyStatement [Statement]
        ';
    by
        Statements [. EmptyStatement] [. Tail]
end rule

rule markAllFuncUnsafe
    replace [Function]
        SafeFunction [SafeFunction]
    deconstruct SafeFunction
        AsyncConstQualifiers [AsyncConstQualifiers?] EXTERN_Abi [EXTERN_Abi?] 'fn FunctionIdentifier [IDENTIFIER]
        Generics [Generics?] '( FunctionParameters [FunctionParameters?] ')
        FunctionReturnType [FunctionReturnType?] WhereClause [WhereClause?]
        SEMI_or_BlockExpression [SEMI_or_BlockExpression]
    by
        AsyncConstQualifiers 'unsafe EXTERN_Abi 'fn FunctionIdentifier Generics
        '( FunctionParameters ')
        FunctionReturnType WhereClause
        SEMI_or_BlockExpression
end rule

rule cleanUnsafePerFunction
    import Global_UnsafeSymbolIds [id*]
    import Global_UnsafeTypeAliasIds [id*]
    replace $ [SafeFunction]
        AsyncConstQualifiers [AsyncConstQualifiers?] EXTERN_Abi [EXTERN_Abi?] 'fn FunctionIdentifier [IDENTIFIER]
        Generics [Generics?] '( FunctionParameters [FunctionParameters?] ')
        FunctionReturnType [FunctionReturnType?] WhereClause [WhereClause?]
        SEMI_or_BlockExpression [SEMI_or_BlockExpression]
    construct UnsafeFuncParamIds [id*]
        _ [_getUnsafeArgIds FunctionParameters]
    construct UnsafeLocalVarIds [id*]
        _ [_getUnsafeLocalVarIds SEMI_or_BlockExpression]
    construct UsedIds [id*]
        _ [^ SEMI_or_BlockExpression] [_sortUniqIds]
    construct UsedUnsafeIds [id*]
        _ [_uniqIds Global_UnsafeSymbolIds each UsedIds]
            [. UnsafeFuncParamIds]
            [. UnsafeLocalVarIds]
    construct LocalPointerVarIds [id*]
        _ [_getPointerVarIdsInFunctionParameters FunctionParameters]
            [_getPointerVarIdsInBody SEMI_or_BlockExpression]
    by
        AsyncConstQualifiers EXTERN_Abi 'fn FunctionIdentifier
        Generics '( FunctionParameters ')
        FunctionReturnType WhereClause
        SEMI_or_BlockExpression [cleanUnsafe UsedUnsafeIds LocalPointerVarIds]
end rule

function _getPointerVarIdsInBody SEMI_or_BlockExpression [SEMI_or_BlockExpression]
    replace [id*]
        Ids [id*]
    construct AllRawPointerLetStatements [LetStatement*]
        _ [^ SEMI_or_BlockExpression] [_onlyPointerLetStatements]
    construct AllLetPatterns [LetPattern*]
        _ [^ AllRawPointerLetStatements]
    by
        Ids [^ AllLetPatterns]
end function

rule _onlyPointerLetStatements
    replace [LetStatement*]
        LetStatement [LetStatement]
        LetStatements [LetStatement*]
    deconstruct not LetStatement
        _ [OuterAttribute*] 'let _ [LetPattern] ': _ [RawPointerType] _ [EQUALS_Expression?] ';
    by
        LetStatements
end rule

function _getPointerVarIdsInFunctionParameters FunctionParameters [FunctionParameters?]
    deconstruct FunctionParameters
        FunctionParams [FunctionParam,+] _ [', ?]
    replace [id*]
        Ids [id*]
    construct PointerFunctionParams [FunctionParam,]
        FunctionParams [_onlyPointerFunctionParams]
    construct AllRawPointerPattern [Pattern*]
        _ [^ PointerFunctionParams]
    by
        Ids [^ AllRawPointerPattern]
end function

rule _onlyPointerFunctionParams
    replace [FunctionParam,]
        FunctionParam [FunctionParam] ,
        FunctionParams [FunctionParam,]
    deconstruct not FunctionParam
        _ [OuterAttribute*] _ [Pattern] ': _ [RawPointerType]
    by
        FunctionParams
end rule

function _getUnsafeLocalVarIds SEMI_or_BlockExpression [SEMI_or_BlockExpression]
    construct AllLetStatements [LetStatement*]
        _ [^ SEMI_or_BlockExpression]
    construct UnsafeLetStatements [LetStatement*]
        AllLetStatements [_onlyUnsafeLetStatements]
    construct UnsafeLetPatterns [LetPattern*]
        _ [^ UnsafeLetStatements]
    replace [id*]
        Ids [id*]
    by
        Ids [^ UnsafeLetPatterns]
end function

rule _onlyUnsafeLetStatements
    import Global_UnsafeTypeAliasIds [id*]
    replace [LetStatement*]
        LetStatement [LetStatement]
        MoreLetStatements [LetStatement*]
    construct UsedIds [id*]
        _ [^ LetStatement]
    where not
        %Global_UnsafeTypeAliasIds [_hasId each UsedIds]
        Global_UnsafeTypeAliasIds [_IdsHasId each UsedIds]
    deconstruct not * [FunctionQualifiers] LetStatement
        _ [AsyncConstQualifiers?] 'unsafe _ [EXTERN_Abi?]
    by
        MoreLetStatements
end rule

function _getUnsafeArgIds FunctionParameters [FunctionParameters?]
    deconstruct FunctionParameters
        FunctionParams [FunctionParam,+] _ [', ?]
    construct UnsafeFunctionParams [FunctionParam,]
        FunctionParams [_onlyFunctionParamWithId] [_onlyUnsafeFunctionParam]
    construct Patterns [Pattern*]
        _ [^ UnsafeFunctionParams]
    replace [id*]
        Ids [id*]
    by
        Ids [^ Patterns]
end function

rule _onlyFunctionParamWithId
    replace [FunctionParam,]
        FunctionParam [FunctionParam],
        FunctionParams [FunctionParam,]
    deconstruct not FunctionParam
        _ [OuterAttribute*] _ [FunctionParamPattern] ': Type [Type]
    by
        FunctionParams
end rule

rule _onlyUnsafeFunctionParam
    replace [FunctionParam,]
        FunctionParam [FunctionParam],
        FunctionParams [FunctionParam,]
    import Global_UnsafeTypeAliasIds [id*]
    deconstruct FunctionParam
        _ [OuterAttribute*] _ [FunctionParamPattern] ': Type [Type]
    construct TypeIds [id*]
        _ [^ Type]
    where not
        Global_UnsafeTypeAliasIds [_IdsHasId each TypeIds]
    where not
        TypeIds [_IdsHasId 'VarList]
    by
        FunctionParams
end rule

function _getAllUnsafeSymbolIds P [program]
    replace [id*]
        _ [id*]
    by
        _   [_getUnsafeSymbolIds P]
 	        [_getUnsafeFuncIds P]
            [_sortUniqIds]
end function

% remove any duplication in ids
function _sortUniqIds
    replace [id*]
        IdA [id]
        IdB [id]
        Ids [id*]
    where
        IdA [> IdB]
    by
        IdB
        IdA
        Ids
end function

function cleanUnsafe UsedUnsafeIds [id*] LocalPointerVarIds [id*]
    replace [SEMI_or_BlockExpression]
        P [SEMI_or_BlockExpression]
    by
        P   [breakUnsafeBlocks]
            [unmarkSafeStatementBlocks UsedUnsafeIds LocalPointerVarIds]
end function

function _getUnsafeSymbolIds P [program]
    construct KnownUnsafeIds [id*]
	    'offset
    construct OptMutStaticIdentifier [OptMutStaticIdentifier*]
	    _ [^ P]
    construct UnsafeFuncParams [FunctionParam*]
        _ [^ P] [_onlyUnsafeParams]
    construct UnsafeFuncParamPatterns [FunctionParamPattern*]
        _ [^ UnsafeFuncParams]
    replace [id*]
        _ [id*]
    by
        KnownUnsafeIds [^ OptMutStaticIdentifier]
            [^ UnsafeFuncParamPatterns]
end function

function _getUnsafeTypeAliases P [program]
    construct UnsafeTypeAliases [TypeAlias*]
        _ [^ P] [_onlyUnsafeTypeAliases]
    construct UnsafeTypeAliasPatterns [TypeAliasPattern*]
        _ [^ UnsafeTypeAliases]
    construct UnsafeTypeIds [id*]
        _ [^ UnsafeTypeAliasPatterns]
    replace [id*]
        _ [id*]
    by
        UnsafeTypeIds
end function

rule _onlyUnsafeTypeAliases
    replace [TypeAlias*]
        TypeAlias [TypeAlias]
        TypeAliases [TypeAlias*]
    deconstruct not * ['unsafe ?] TypeAlias
        'unsafe
    by
        TypeAliases
end rule

rule _onlyUnsafeParams
    replace [FunctionParam*]
        FuncParam [FunctionParam]
        OtherFuncParams [FunctionParam*]
    deconstruct not * ['unsafe ?] FuncParam
	    'unsafe
    by
	    OtherFuncParams
end rule

% sink unsafe keyword from function declaration into function body
rule sinkUnsafe
    replace [Function]
        AsyncConstQualifiers [AsyncConstQualifiers?] 'unsafe ExternAbi [EXTERN_Abi?]
        'fn FuncName [IDENTIFIER] Generics [Generics?]
            '( Parameters [FunctionParameters?] ')
            FuncReturnType [FunctionReturnType?] WhereClause [WhereClause?]
        LoopLabel [LoopLabel?]
        '{
            InnerAttributes [InnerAttribute*]
            Statements [Statements]
        '}
    % if it's variadic, the function itself is unsafe
    deconstruct not * [VariadicType] Parameters
        '...
    % otherwise, sink unsafe to the function statements
    by
        AsyncConstQualifiers ExternAbi
        'fn FuncName Generics
            '( Parameters ')
            FuncReturnType WhereClause
        LoopLabel
        '{
            unsafe {
                InnerAttributes
                Statements
            }
        '}
end rule


% break all unsafe block into unsafe blocks each containing only
% one Statement
rule breakUnsafeBlocks
    replace [Statement*]
        'unsafe
        '{
            FirstStatement [Statement]
            SecondStatement [Statement]
            TailStatements [Statement*]
        '}
        Tail [Statement*]
    by
        'unsafe {
            FirstStatement
        }
        'unsafe {
            SecondStatement
        }
        'unsafe
        {
            TailStatements
        }
	    Tail
end rule

rule unmarkSafeStatementBlocks UsedUnsafeIds [id*] LocalPointerVarIds [id*]
    % optimization to unlabel safe statements
    replace [Statement*]
        'unsafe
        '{
            Statement [Statement]
        '}
	    MoreStatements [Statement*]
    where
	    Statement [_isSafe UsedUnsafeIds LocalPointerVarIds]
    by
        Statement [_endExpnStatWithSemi]
        MoreStatements
end rule

% avoid case when original unsafe block's ExpressionStatement doesn't end
% with a semicolon, which is ok if the block is not removed, but not ok
% when it is removed, e.g. call to main_0 in
% ptrdist-1.1/ft/rust_rs2rs/src/ft.rs
% For now we call this rule only on Statement, so this shouldn't run into
% cases where block's resulting value is used, in which case it would be
% an Expression instead of Statement?
function _endExpnStatWithSemi
    replace [Statement]
        Expn [ExpressionWithoutBlock] Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    by
        Expn Infix_Postfix_Expressions ';
end function

function _isSafe UsedUnsafeIds [id*] LocalPointerVarIds [id*]
    match [Statement]
	    Statement [Statement]
    % for now, a statement is unsafe if: it refers to an unsafe identifier,
    where not
        Statement [_StatementHasId each UsedUnsafeIds]
    % asm! macro is unsafe
    deconstruct not * [MacroSimplePath] Statement
        asm
    where not
        Statement [_hasDerefRawPointer each LocalPointerVarIds]
    % having raw pointer type is safe, as long as it is not referenced.
    %deconstruct not * [TypeNoBounds] Statement
    %    _ [RawPointerType]
    % otherwise, it's safe
end function

function _hasDerefRawPointer PointerId [id]
    match [Statement]
        Statement [Statement]
    %construct PointerIdTokenTree [TokenTree*]
    %    _ [parse PointerId]
    %deconstruct * [TokenTree*] Statement
    %    * PointerIdTokenTree

    % Comments:The above two blocks commented 
    % consider raw pointer as type of TokenTree, 
    % but we found different cognition from the 
    % parsing tree, so keep the old one as comments
    % and try the new one, meanwhile, keep one eye
    % on this type 
    deconstruct * [Expression] Statement
        * PointerId
end function

% concatenate two consecutive unsafe blocks into one
rule concatenateUnsafeBlocks
    replace [Statement*]
        'unsafe
        {
            FirstStatements [Statement*]
        }
        'unsafe
        {
            SecondStatements [Statement*]
        }
        Tail [Statement*]
    by
        'unsafe {
            FirstStatements [. SecondStatements]
        }
	    Tail
end rule

rule rmEmptyUnsafeBlockExpression
    replace [Statement*]
        'unsafe {}
        Tail [Statement*]
    by
        Tail
end rule

% if a local var is declared in unsafe block, then later reference
% to this var must also be in the unsafe block. Here we find such
% case and shift these statements into unsafe block.
rule shiftStatementIntoUnsafeBlock
    replace [Statement*]
        UnsafeBlock [UnsafeBlockExpression]
        FollowingStatements [Statement*]
    % what does the block define?
    construct MutStaticIdentifiers [MutStaticIdentifier*]
	    _ [^ UnsafeBlock]
    construct UnsafeLocalVarIds [id*]
        _ [_getAllLocalVarIdsInUnsafeBlock UnsafeBlock] [^ MutStaticIdentifiers]
    % are any of those used in the following statements?
    where
        FollowingStatements [_StatementsHasId each UnsafeLocalVarIds]
    deconstruct UnsafeBlock
        'unsafe {
            UnsafeStatements [Statement*]
        }
    deconstruct FollowingStatements
        FirstFollowingStatement [Statement]
        RestOfFollowingStatements [Statement*]
    construct ShiftedStatements [Statement*]
        'unsafe {
            UnsafeStatements [. FirstFollowingStatement]
        }
	    RestOfFollowingStatements
    by
        ShiftedStatements [concatenateUnsafeBlocks]
end rule

function _getUnsafeFuncIds P [program]
    construct KnownRustUnsafeFuncIds [id*]
        'from_raw_parts 'from_utf8_unchecked 'as_mut_vec 'build_str_from_raw_ptr
        'transmute 'write_volatile
    construct AllUnsafeFunctionIdentifiers [UnsafeFunctionIdentifier*]
        _ [^ P]
    % for now we assume that all external functions are unsafe
    construct AllExternalFuncs [ExternalFunctionIdentifier*]
        _ [^ P]
    replace [id*]
        Ids [id*]
    by
        Ids [. KnownRustUnsafeFuncIds] [^ AllUnsafeFunctionIdentifiers] [^ AllExternalFuncs]
end function

function _getAllLocalVarIdsInUnsafeBlock UnsafeBlock [UnsafeBlockExpression]
    replace [id*]
        _ [id*]
    construct AllLetPatterns [LetPattern*]
        _ [^ UnsafeBlock]
    by
        _ [^ AllLetPatterns]
end function

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
