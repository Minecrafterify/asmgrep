package com.asmgrep;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Objects;

/** A matching line. */
public final class Match {
    private final long lineNumber;
    private final byte[] raw;

    Match(long lineNumber, byte[] raw) {
        this.lineNumber = lineNumber;
        this.raw = raw;
    }

    /** 1-based line number. */
    public long getLineNumber() {
        return lineNumber;
    }

    /** Line text decoded as UTF-8, without the line terminator. */
    public String getText() {
        return new String(raw, StandardCharsets.UTF_8);
    }

    /** Exact bytes of the line. */
    public byte[] getBytes() {
        return raw.clone();
    }

    @Override
    public boolean equals(Object o) {
        if (!(o instanceof Match)) {
            return false;
        }
        Match m = (Match) o;
        return lineNumber == m.lineNumber && Arrays.equals(raw, m.raw);
    }

    @Override
    public int hashCode() {
        return Objects.hash(lineNumber, Arrays.hashCode(raw));
    }

    @Override
    public String toString() {
        return lineNumber + ": " + getText();
    }
}
