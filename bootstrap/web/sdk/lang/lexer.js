/** suigui lexer — brace markup, quoted strings, bare numbers/flags. */

export class LexError extends Error {
  constructor(message, line, col) {
    super(`${message} at ${line}:${col}`);
    this.line = line;
    this.col = col;
    this.name = "LexError";
  }
}

/**
 * @typedef {{ type: string, value?: any, line: number, col: number }} Token
 */

export function lex(source) {
  const tokens = [];
  let i = 0;
  let line = 1;
  let col = 1;

  const peek = () => source[i];
  const advance = () => {
    const ch = source[i++];
    if (ch === "\n") {
      line++;
      col = 1;
    } else {
      col++;
    }
    return ch;
  };

  const push = (type, value) => {
    tokens.push({ type, value, line, col });
  };

  while (i < source.length) {
    const startLine = line;
    const startCol = col;
    const ch = peek();

    if (ch === " " || ch === "\t" || ch === "\r" || ch === "\n") {
      advance();
      continue;
    }

    if (ch === "/" && source[i + 1] === "/") {
      while (i < source.length && peek() !== "\n") advance();
      continue;
    }

    if (ch === "/" && source[i + 1] === "*") {
      advance();
      advance();
      while (i < source.length && !(peek() === "*" && source[i + 1] === "/")) advance();
      if (i >= source.length) throw new LexError("Unterminated block comment", startLine, startCol);
      advance();
      advance();
      continue;
    }

    if (ch === '"') {
      advance();
      let s = "";
      while (i < source.length && peek() !== '"') {
        if (peek() === "\\") {
          advance();
          const esc = advance();
          if (esc === "n") s += "\n";
          else if (esc === "t") s += "\t";
          else if (esc === '"') s += '"';
          else if (esc === "\\") s += "\\";
          else if (esc === "'") s += "'";
          else s += esc;
        } else {
          s += advance();
        }
      }
      if (peek() !== '"') throw new LexError("Unterminated string", startLine, startCol);
      advance();
      tokens.push({ type: "string", value: s, line: startLine, col: startCol });
      continue;
    }

    if (ch === "'") {
      advance();
      let s = "";
      while (i < source.length && peek() !== "'") {
        if (peek() === "\\") {
          advance();
          const esc = advance();
          if (esc === "n") s += "\n";
          else if (esc === "t") s += "\t";
          else if (esc === "'") s += "'";
          else if (esc === "\\") s += "\\";
          else if (esc === '"') s += '"';
          else s += esc;
        } else {
          s += advance();
        }
      }
      if (peek() !== "'") throw new LexError("Unterminated string", startLine, startCol);
      advance();
      tokens.push({ type: "string", value: s, line: startLine, col: startCol });
      continue;
    }

    if (/[0-9]/.test(ch) || (ch === "-" && /[0-9]/.test(source[i + 1] || ""))) {
      let num = advance();
      while (i < source.length && /[0-9.]/.test(peek())) num += advance();
      tokens.push({ type: "number", value: Number(num), line: startLine, col: startCol });
      continue;
    }

    if (ch === "#") {
      advance();
      let id = "";
      if (i < source.length && /[A-Za-z_]/.test(peek())) {
        while (i < source.length && /[A-Za-z0-9_]/.test(peek())) id += advance();
      }
      if (!id) throw new LexError("Expected id after #", startLine, startCol);
      tokens.push({ type: "hashid", value: id, line: startLine, col: startCol });
      continue;
    }

    if (/[A-Za-z_]/.test(ch)) {
      let id = "";
      while (i < source.length && /[A-Za-z0-9_]/.test(peek())) id += advance();
      tokens.push({ type: "ident", value: id, line: startLine, col: startCol });
      continue;
    }

    const singles = {
      "{": "lbrace",
      "}": "rbrace",
      "(": "lparen",
      ")": "rparen",
      "=": "eq",
      "+": "plus",
      "-": "minus",
      "*": "star",
      "/": "slash",
      ".": "dot",
      ",": "comma",
    };
    if (singles[ch]) {
      advance();
      tokens.push({ type: singles[ch], line: startLine, col: startCol });
      continue;
    }

    throw new LexError(`Unexpected character '${ch}'`, startLine, startCol);
  }

  tokens.push({ type: "eof", line, col });
  return tokens;
}
