##
# LR parser generated by the Syntax tool.
#
# https://www.npmjs.com/package/syntax-cli
#
#     npm install -g syntax-cli
#
#     syntax-cli --help
#
# To regenerate run:
#
#     syntax-cli \
#         --grammar ~/path-to-grammar-file \
#         --mode <parsing-mode> \
#         --output ~/parsermodule.py
##

yytext = ''
yyleng = 0

# Semantic value result.
__ = None

# Location restult.
__loc = None

should_capture_locations = {{{CAPTURE_LOCATIONS}}}

EOF = '$'

def on_parse_begin(string):
    pass

def on_parse_end(parsed):
    pass

{{{MODULE_INCLUDE}}}

{{{PRODUCTION_HANDLERS}}}

productions = {{{PRODUCTIONS}}}
tokens = {{{TOKENS}}}
table = {{{TABLE}}}

stack = None

{{{TOKENIZER}}}

def set_tokenizer(custom_tokenizer):
    global _tokenizer
    _tokenizer = custom_tokenizer

def get_tokenizer():
    return _tokenizer

def yyloc(start, end):
    # Epsilon doesn't produce location.
    if (start is None or end is None):
        return end if start is None else start

    return {
        'start_offset': start['start_offset'],
        'end_offset': end['end_offset'],
        'start_line': start['start_line'],
        'end_line': end['end_line'],
        'start_column': start['start_column'],
        'end_column': end['end_column'],
    }

def parse(string):
    global __, __loc, yytext, yyleng

    on_parse_begin(string)

    if _tokenizer is None:
        raise Exception('_tokenizer instance wasn\'t specified.')

    _tokenizer.init_string(string)

    # Init the stack with start state 0.
    stack = [0]

    token = _tokenizer.get_next_token()
    shifted_token = None

    while True:
        if token is None:
            _unexpected_end_of_input()

        state = stack[-1]
        column = tokens[token['type']]

        if not column in table[state].keys():
            _unexpected_token(token)

        entry = table[state][column]

        # Shift.
        if entry[0] == 's':
            loc = None

            if should_capture_locations:
                loc = {
                  'start_offset': token['start_offset'],
                  'end_offset': token['end_offset'],
                  'start_line': token['start_line'],
                  'end_line': token['end_line'],
                  'start_column': token['start_column'],
                  'end_column': token['end_column'],
                }

            stack.extend((
                {
                    'symbol': tokens[token['type']],
                    'semantic_value': token['value'],
                    'loc': loc,
                },
                int(entry[1:]) # Next state.
            ))
            shifted_token = token
            token = _tokenizer.get_next_token()

        # Reduce.
        elif entry[0] == 'r':
            production = productions[int(entry[1:])]
            has_semantic_action = len(production) > 2

            semantic_value_args = None
            location_args = None

            if has_semantic_action:
                semantic_value_args = []

                if should_capture_locations:
                    location_args = []

            if production[1] != 0:
                rhs_length = production[1]

                while rhs_length > 0:
                    stack.pop()
                    stack_entry = stack.pop()

                    if has_semantic_action:
                        semantic_value_args.insert(0, stack_entry['semantic_value'])

                        if not location_args is None:
                            location_args.insert(0, stack_entry['loc'])

                    rhs_length = rhs_length - 1

            reduce_stack_entry = {'symbol': production[0]}

            if has_semantic_action:
                yytext = shifted_token != None and shifted_token['value'] or None
                yyleng = shifted_token != None and len(shifted_token['value']) or 0

                semantic_action_args = semantic_value_args

                if not location_args is None:
                    semantic_action_args = semantic_value_args + location_args

                production[2](*semantic_action_args)
                reduce_stack_entry['semantic_value'] = __

                if not location_args is None:
                    reduce_stack_entry['loc'] = __loc

                next_state = stack[-1]
                symbol_to_reduce_with = str(production[0])

            stack.extend((reduce_stack_entry, table[next_state][symbol_to_reduce_with]))

        elif entry == 'acc':
            stack.pop()
            parsed = stack.pop()

            if len(stack) != 1 or stack[0] != 0 or _tokenizer.has_more_tokens():
                _unexpected_token(token)

            if 'semantic_value' in parsed:
                on_parse_end(parsed['semantic_value'])
                return parsed['semantic_value']

            on_parse_end(True)
            return True

        if not _tokenizer.has_more_tokens() and len(stack) <= 1:
            break

def _unexpected_token(token):
    if token['type'] == EOF:
        _unexpected_end_of_input()

    _tokenizer.throw_unexpected_token(
        token['value'],
        token['start_line'],
        token['start_column']
    )

def _unexpected_end_of_input():
    _parse_error('Unexpected end of input.')

def _parse_error(message):
    raise Exception('SyntaxError: ' + str(message))


