package com.asmgrep;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

public final class AsmgrepTest {
    private static int failures;

    private static void check(boolean cond, String what) {
        if (!cond) {
            System.err.println("check failed: " + what);
            failures++;
        }
    }

    public static void main(String[] args) throws Exception {
        Path file = Files.createTempFile("asmgrep-java", ".txt");
        try {
            Files.write(file, "one\ntwo ERROR\nthree\nlast ERROR".getBytes(StandardCharsets.UTF_8));
            List<Match> results = Asmgrep.search("ERROR", file.toString());
            check(results.size() == 2, "count");
            check(results.get(0).getLineNumber() == 2, "first line number");
            check(results.get(0).getText().equals("two ERROR"), "first text");
            check(results.get(1).getLineNumber() == 4, "second line number");
            check(Asmgrep.searchScalar("ERROR", file.toString()).equals(results), "scalar parity");

            Files.write(file, new byte[0]);
            check(Asmgrep.search("x", file.toString()).isEmpty(), "empty file");

            for (int i = 0; i < 500; i++) {
                Asmgrep.search("x", file);
            }

            boolean threw = false;
            try {
                Asmgrep.search("x", "/nonexistent/file");
            } catch (AsmgrepException e) {
                threw = e.getStatus() == -2;
            }
            check(threw, "missing file raises AsmgrepException");

            List<Match> buf = Asmgrep.searchBytes("b".getBytes(StandardCharsets.UTF_8),
                    "a\nabc\nc".getBytes(StandardCharsets.UTF_8));
            check(buf.size() == 1 && buf.get(0).getText().equals("abc"), "buffer search");
            check(Asmgrep.version().equals("1.0.0"), "version");
        } finally {
            Files.deleteIfExists(file);
        }
        if (failures != 0) {
            System.exit(1);
        }
        System.out.println("Java tests passed");
    }
}
