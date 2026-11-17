package com.asmgrep;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * Java interface to the asmgrep native search engine.
 *
 * <p>All searching is done by libasmgrep through JNI. The native library
 * {@code libasmgrep-jni.so} must be on {@code java.library.path}.
 */
public final class Asmgrep {
    private static final int FLAG_SCALAR = 0x1;

    static {
        System.loadLibrary("asmgrep-jni");
    }

    private Asmgrep() {
    }

    /** Returns the lines of the file at {@code filename} containing {@code pattern}. */
    public static List<Match> search(String pattern, String filename) {
        return searchFile(pattern, filename, false);
    }

    public static List<Match> search(String pattern, Path file) {
        return searchFile(pattern, file.toString(), false);
    }

    /** As {@link #search(String, String)}, using the scalar reference engine. */
    public static List<Match> searchScalar(String pattern, String filename) {
        return searchFile(pattern, filename, true);
    }

    /** Returns the lines of {@code data} containing {@code pattern}. */
    public static List<Match> searchBytes(byte[] pattern, byte[] data) {
        long handle = nativeSearchBuffer(data, pattern, 0);
        return collect(handle);
    }

    /** Returns the native library version. */
    public static String version() {
        return nativeVersion();
    }

    private static List<Match> searchFile(String pattern, String filename, boolean scalar) {
        byte[] pat = pattern.getBytes(StandardCharsets.UTF_8);
        for (byte b : pat) {
            if (b == 0) {
                throw new IllegalArgumentException("file search patterns cannot contain NUL");
            }
        }
        byte[] path = filename.getBytes(StandardCharsets.UTF_8);
        long handle = nativeSearchFile(Arrays.copyOf(pat, pat.length + 1),
                Arrays.copyOf(path, path.length + 1), scalar ? FLAG_SCALAR : 0);
        return collect(handle);
    }

    private static List<Match> collect(long handle) {
        try {
            int count = nativeCount(handle);
            List<Match> out = new ArrayList<>(count);
            for (int i = 0; i < count; i++) {
                out.add(new Match(nativeLineNumber(handle, i), nativeText(handle, i)));
            }
            return Collections.unmodifiableList(out);
        } finally {
            nativeFree(handle);
        }
    }

    private static native long nativeSearchFile(byte[] patternZ, byte[] pathZ, int flags);

    private static native long nativeSearchBuffer(byte[] data, byte[] pattern, int flags);

    private static native int nativeCount(long handle);

    private static native long nativeLineNumber(long handle, int index);

    private static native byte[] nativeText(long handle, int index);

    private static native void nativeFree(long handle);

    private static native String nativeVersion();
}
