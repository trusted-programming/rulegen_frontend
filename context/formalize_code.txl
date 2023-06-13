include "rust.grm"

function main
    replace [program]
        P [program]
    by
        P   [addSemicolonAfterBlockExpn]
end function

% to adjust misparse of statement after a block expression that doesn't end
% with semicolon to be part of the block expression's postfix, we force a
% semicolon after all block expressions.
rule addSemicolonAfterBlockExpn
    replace [Statement*]
        ExpressionStatement [ExpressionStatement]
        Statements [Statement*]
    deconstruct ExpressionStatement
        Expression [Expression] _ ['; ?]
    deconstruct Expression
        Prefix_Expressions [Prefix_Expressions*]
        ExpressionWithBlock [ExpressionWithBlock]
        Infix_Postfix_Expressions [Infix_Postfix_Expressions*]
    deconstruct Infix_Postfix_Expressions
        _ [Infix_Postfix_Expressions+]
    %construct Length [number]
    %    _ [length Infix_Postfix_Expressions]
    %where
    %    Length [> 0]
    construct OriginalStatement [Statement]
        Prefix_Expressions ExpressionWithBlock ';
    construct TmpExpns [Expression*]
        _ [reparse Infix_Postfix_Expressions] %[print]
    deconstruct TmpExpns
        NewExpn [Expression]
    construct NewStatement [Statement]
        NewExpn ';
    by
        OriginalStatement
        NewStatement
        Statements
end rule