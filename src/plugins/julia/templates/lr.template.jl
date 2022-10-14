module SyntaxParser

#=
  LR parser generated by the Syntax tool.

  https://www.npmjs.com/package/syntax-cli

    npm install -g syntax-cli

    syntax-cli --help

  To regenerate run:

    syntax-cli \
      --grammar ~/path-to-grammar-file \
      --mode <parsing-mode> \
      --output ~/ParserClassName.jl
=#

# --------------------------------------------------------------
# Shared includes
using DataStructures

# Basic constants and globals - should capture locations is inserted by the parser generator based on parameters given to the command line
const EOF = "\$"
const should_capture_locations = {{{CAPTURE_LOCATIONS}}}

# Types
struct SyntaxError <: Exception
    msg::String
end

function Base.showerror(io::IO, err::SyntaxError)
    print(io, err.msg)
end

Base.@kwdef mutable struct yyLoc
    startoffset::Int
    endoffset::Int
    startline::Int
    endline::Int
    startcolumn::Int
    endcolumn::Int
end

Base.@kwdef mutable struct StackEntry
    symbol::Int
    semanticvalue::Any
    loc::Union{yyLoc, Nothing}
end

Base.@kwdef mutable struct ParserData
    yytext::String
    yylength::Int = 0
    __res = nothing
    __loc = nothing
end

# --------------------------------------------------------------
# Tokenizer.

{{{TOKENIZER}}}

# --------------------------------------------------------------
# Parser implementation

function yyloc(start, ending)
    !should_capture_locations && return nothing

    if isnothing(start) || isnothing(ending)
        return isnothing(start) ? ending : start
    end

    return yyLoc(
        startoffset = start.startoffset,
        endoffset = ending.endoffset,
        startline = start.startline,
        endline = ending.endline,
        startcolumn = start.startcolumn,
        endcolumn = ending.endcolumn
    )
end

function yyloc(token)
    !should_capture_locations && return nothing
    isnothing(token) && return nothing
    return yyLoc(
        startoffset = token.startoffset,
        endoffset = token.endoffset,
        startline = token.startline,
        endline = token.endline,
        startcolumn = token.startcolumn,
        endcolumn = token.endcolumn
    )
end

{{{PRODUCTION_HANDLERS}}}

# Constant mappings inserted by the parser generator by processing the grammar definition 
const productions = {{{PRODUCTIONS}}} # [[1, 2, "handler1"], [3, 4, "handler2], ...] i.e. Vector{Vector{Union{Integer, String}}}
const table = {{{TABLE}}} # i.e. Dict{Int, String}

# blank stand-ins for begin and end
function parsebegin() end

function parseend(value) end

# --------------------------------------------------------------
# Module includes provided by the grammar.
{{{MODULE_INCLUDE}}}

#=
  Primary parsing function
    ss - the code to parse, in a String
    onParseBegin - a function to call when parsing begins
    onParseEnd - a function to call when parsing ends, should accept as a single argument with the parsed value result
=#
function parse(ss::AbstractString; tokenizerinitfunction::Function = inittokenizer, onparsebegin::Function = parsebegin, onparseend::Function = parseend)
    # initialize our parser data
    parserdata = ParserData(yytext = "", yylength = 0, __res = nothing, __loc = nothing)

    # initialization and prep for parsing
    !isnothing(onparsebegin) && onparsebegin()
    tokenizerdata = tokenizerinitfunction(ss)
    stack = Stack{Union{StackEntry,Int}}()
    push!(stack, 0)

    # begin parsing
    token = getnexttoken!(parserdata, tokenizerdata)::Token
    shiftedtoken = nothing
    while hasmoretokens(tokenizerdata) || !isempty(stack)
        # get a token and look it up in our parsing table
        isnothing(token) && unexpectedendofinput()
        state = first(stack)
        column = token.type
        entry = get(table[state+1], column, nothing)
        if isnothing(entry)
            unexpectedtoken(tokenizerdata, token)
            break
        end

        # found 'shift' instruction, which starts with s then has <next state number> - i.e. s5 means "shift to state 5"
        if entry[1] == 's'
            push!(stack, StackEntry(symbol = token.type, semanticvalue = token.value, loc = yyloc(token)))
            push!(stack, tryparse(Int, SubString(entry, 2)))
            shiftedtoken = token
            token = getnexttoken!(parserdata, tokenizerdata)::Token

            # found "reduce" instruction, which starts with r then has <production number> to reduce by - i.e. r2 means "reduce by production 2"
        elseif entry[1] == 'r'
            production = productions[tryparse(Int, SubString(entry, 2))+1]

            # Handler can be optional: [0, 3] - no handler, [0, 3, "_handler1"] - has handler.
            hassemanticaction = length(production) > 2
            semanticvalueargs = Vector()
            locationargs = should_capture_locations ? Vector() : nothing
            rhslength = production[2]
            if rhslength != 0
                while rhslength > 0
                    # pop the state number
                    pop!(stack)

                    # pop the stack entry
                    stackentry = pop!(stack)

                    # collection all the semantic values from the stack to the argument list, which will be passed to the action handler
                    if hassemanticaction
                        pushfirst!(semanticvalueargs, stackentry.semanticvalue)
                        should_capture_locations && pushfirst!(locationargs, stackentry.loc)
                    end
                    rhslength -= 1
                end
            end
            previousstate = first(stack)
            symboltoproducewith = production[1]
            reducestackentry = StackEntry(symbol = symboltoproducewith, semanticvalue = nothing, loc = nothing)
            if hassemanticaction
                parserdata.yytext = isnothing(shiftedtoken) ? nothing : shiftedtoken.value
                parserdata.yylength = isnothing(shiftedtoken) ? 0 : length(shiftedtoken.value)
                semanticactionhandler = getfield(SyntaxParser, Symbol(production[3]))
                semanticactionargs = semanticvalueargs
                if should_capture_locations
                    semanticactionargs = vcat(semanticactionargs, locationargs)
                end

                # call the handler the result is put in __res, which is accessed/assigned to by for example $$ = <something> in the grammar
                semanticactionhandler(parserdata, semanticactionargs...)
                reducestackentry.semanticvalue = parserdata.__res
                if should_capture_locations
                    reducestackentry.loc = parserdata.__loc
                end
            end
            push!(stack, reducestackentry)
            push!(stack, tryparse(Int, table[previousstate+1][symboltoproducewith]))

            # Accepted; time to pop the starting production and it's state number
        elseif entry == "acc"
            # pop the state number and get the parsed value 
            pop!(stack)
            parsed = pop!(stack)

            # Check for if the stack has other stuff on it, which would be bad
            if length(stack) != 1 || first(stack) != 0 || hasmoretokens(tokenizerdata)
                unexpectedtoken(tokenizerdata, token)
            end

            # success!
            parsedvalue = parsed.semanticvalue
            !isnothing(onparseend) && onparseend(parsedvalue)
            return parsedvalue
        end
    end

    # if we got here, we failed to parse and failed to throw an exception about why we failed to parse...
    return nothing
end

function unexpectedtoken(tokenizerdata::TokenizerData, token::Token)
    if token.type == EOF_TOKEN.type
        unexpectedendofinput()
    else
        throwunexpectedtoken(tokenizerdata, token.value, token.startline, token.startcolumn)
    end
end

function unexpectedendofinput()
    parseerror("Unexpected end of input.")
end

function parseerror(message)
    throw(SyntaxError(message))
end

end # module