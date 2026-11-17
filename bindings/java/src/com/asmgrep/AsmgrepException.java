package com.asmgrep;

/** Raised when a search fails. */
public class AsmgrepException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    private final int status;

    public AsmgrepException(int status, String message) {
        super(message);
        this.status = status;
    }

    /** Negative errno value reported by the native library. */
    public int getStatus() {
        return status;
    }
}
