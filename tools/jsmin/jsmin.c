/*
 * JSMin (C) adapted from Douglas Crockford's reference implementation.
 * This build-time utility minifies JavaScript from an input file to an output file.
 */

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>

static int theA;
static int theB;
static int theLookahead = EOF;
static FILE *infile;
static FILE *outfile;

static int is_alphanum(int c) {
    return (c >= 'a' && c <= 'z') ||
           (c >= '0' && c <= '9') ||
           (c >= 'A' && c <= 'Z') ||
           c == '_' || c == '$' || c == '\\' || c > 126;
}

static int get_char(void) {
    int c = theLookahead;
    theLookahead = EOF;
    if (c == EOF) {
        c = getc(infile);
    }
    if (c >= ' ' || c == '\n' || c == EOF) {
        return c;
    }
    if (c == '\r') {
        return '\n';
    }
    return ' ';
}

static int peek_char(void) {
    theLookahead = get_char();
    return theLookahead;
}

static int next_char(void) {
    int c = get_char();
    if (c == '/') {
        int p = peek_char();
        if (p == '/') {
            for (;;) {
                c = get_char();
                if (c <= '\n') {
                    return c;
                }
            }
        }
        if (p == '*') {
            (void)get_char();
            for (;;) {
                switch (get_char()) {
                    case '*':
                        if (peek_char() == '/') {
                            (void)get_char();
                            return ' ';
                        }
                        break;
                    case EOF:
                        fprintf(stderr, "jsmin: unterminated comment\n");
                        exit(1);
                    default:
                        break;
                }
            }
        }
    }
    return c;
}

static void action(int d) {
    if (d <= 1) {
        putc(theA, outfile);
    }
    if (d <= 2) {
        theA = theB;
        if (theA == '\'' || theA == '"' || theA == '`') {
            for (;;) {
                putc(theA, outfile);
                theA = get_char();
                if (theA == theB) {
                    break;
                }
                if (theA == '\\') {
                    putc(theA, outfile);
                    theA = get_char();
                }
                if (theA == EOF) {
                    fprintf(stderr, "jsmin: unterminated string literal\n");
                    exit(1);
                }
            }
        }
    }
    if (d <= 3) {
        theB = next_char();
        if (theB == '/' &&
            (theA == '(' || theA == ',' || theA == '=' || theA == ':' ||
             theA == '[' || theA == '!' || theA == '&' || theA == '|' ||
             theA == '?' || theA == '+' || theA == '-' || theA == '~' ||
             theA == '*' || theA == '/' || theA == '{' || theA == '}' ||
             theA == ';')) {
            putc(theA, outfile);
            putc(theB, outfile);
            for (;;) {
                theA = get_char();
                if (theA == '[') {
                    for (;;) {
                        putc(theA, outfile);
                        theA = get_char();
                        if (theA == ']') {
                            break;
                        }
                        if (theA == '\\') {
                            putc(theA, outfile);
                            theA = get_char();
                        }
                        if (theA == EOF) {
                            fprintf(stderr, "jsmin: unterminated character class in regex\n");
                            exit(1);
                        }
                    }
                } else if (theA == '/') {
                    break;
                } else if (theA == '\\') {
                    putc(theA, outfile);
                    theA = get_char();
                }
                if (theA == EOF) {
                    fprintf(stderr, "jsmin: unterminated regex literal\n");
                    exit(1);
                }
                putc(theA, outfile);
            }
            theB = next_char();
        }
    }
}

static void jsmin_run(void) {
    theA = '\n';
    action(3);
    while (theA != EOF) {
        switch (theA) {
            case ' ':
                if (is_alphanum(theB)) {
                    action(1);
                } else {
                    action(2);
                }
                break;
            case '\n':
                switch (theB) {
                    case '{':
                    case '[':
                    case '(':
                    case '+':
                    case '-':
                    case '!':
                    case '~':
                        action(1);
                        break;
                    case ' ':
                        action(3);
                        break;
                    default:
                        if (is_alphanum(theB)) {
                            action(1);
                        } else {
                            action(2);
                        }
                        break;
                }
                break;
            default:
                switch (theB) {
                    case ' ':
                        if (is_alphanum(theA)) {
                            action(1);
                        } else {
                            action(3);
                        }
                        break;
                    case '\n':
                        switch (theA) {
                            case '}':
                            case ']':
                            case ')':
                            case '+':
                            case '-':
                            case '"':
                            case '\'':
                            case '`':
                                action(1);
                                break;
                            default:
                                if (is_alphanum(theA)) {
                                    action(1);
                                } else {
                                    action(3);
                                }
                                break;
                        }
                        break;
                    default:
                        action(1);
                        break;
                }
                break;
        }
    }
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: jsmin <input.js> <output.js>\n");
        return 2;
    }

    infile = fopen(argv[1], "rb");
    if (!infile) {
        fprintf(stderr, "jsmin: unable to open input: %s\n", argv[1]);
        return 1;
    }

    outfile = fopen(argv[2], "wb");
    if (!outfile) {
        fclose(infile);
        fprintf(stderr, "jsmin: unable to open output: %s\n", argv[2]);
        return 1;
    }

    jsmin_run();

    if (fclose(outfile) != 0) {
        fclose(infile);
        fprintf(stderr, "jsmin: failed writing output\n");
        return 1;
    }
    fclose(infile);
    return 0;
}
