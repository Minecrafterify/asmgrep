
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.TimeUnit;

public final class RecursiveStress10k {

    private static final Path ASM =
            Path.of("./build/asmgrep").toAbsolutePath();

    private static final Path GREP =
            Path.of("/usr/bin/grep");

    private static final int FILE_COUNT = 10_000;
    private static final int DIRECTORY_COUNT = 100;
    private static final String PATTERN = "needle";
    private static final long TIMEOUT_SECONDS = 180;

    private static int passed;
    private static int failed;

    private record Result(
            int exitCode,
            String stdout,
            String stderr,
            double seconds
    ) {}

    private static Result execute(
            List<String> command,
            Path stdoutFile,
            Path stderrFile
    ) throws Exception {

        ProcessBuilder builder = new ProcessBuilder(command);

        builder.redirectOutput(stdoutFile.toFile());
        builder.redirectError(stderrFile.toFile());

        long start = System.nanoTime();

        Process process = builder.start();

        boolean completed = process.waitFor(
                TIMEOUT_SECONDS,
                TimeUnit.SECONDS
        );

        double seconds =
                (System.nanoTime() - start) / 1_000_000_000.0;

        if (!completed) {
            process.destroyForcibly();
            process.waitFor();

            throw new IOException("Process timed out: " + command);
        }

        return new Result(
                process.exitValue(),
                Files.readString(stdoutFile, StandardCharsets.UTF_8),
                Files.readString(stderrFile, StandardCharsets.UTF_8),
                seconds
        );
    }

    private static List<String> normalize(String output) {
        List<String> lines = new ArrayList<>(
                output.lines().toList()
        );

        Collections.sort(lines);
        return lines;
    }

    private static void test(
            String label,
            String mode,
            Path root,
            Path temp
    ) throws Exception {

        System.out.println("\n===== " + label + " =====");

        Path asmOut = temp.resolve("asm.stdout");
        Path asmErr = temp.resolve("asm.stderr");
        Path grepOut = temp.resolve("grep.stdout");
        Path grepErr = temp.resolve("grep.stderr");

        List<String> asmCommand = List.of(
                ASM.toString(),
                mode,
                PATTERN,
                root.toString()
        );

        List<String> grepCommand = List.of(
                GREP.toString(),
                mode,
                "-F",
                PATTERN,
                root.toString()
        );

        Result asm = execute(asmCommand, asmOut, asmErr);
        Result grep = execute(grepCommand, grepOut, grepErr);

        List<String> asmLines = normalize(asm.stdout());
        List<String> grepLines = normalize(grep.stdout());

        boolean success =
                asm.exitCode() == grep.exitCode()
                && asmLines.equals(grepLines);

        System.out.printf(
                "asmgrep: %.3f seconds, exit=%d, lines=%d%n",
                asm.seconds(),
                asm.exitCode(),
                asmLines.size()
        );

        System.out.printf(
                "GNU grep: %.3f seconds, exit=%d, lines=%d%n",
                grep.seconds(),
                grep.exitCode(),
                grepLines.size()
        );

        if (success) {
            passed++;
            System.out.println("RESULT: PASS");
        } else {
            failed++;
            System.out.println("RESULT: FAIL");

            int limit = Math.min(
                    Math.min(asmLines.size(), grepLines.size()),
                    10
            );

            for (int i = 0; i < limit; i++) {
                if (!asmLines.get(i).equals(grepLines.get(i))) {
                    System.out.println(
                            "asmgrep: " + asmLines.get(i)
                    );
                    System.out.println(
                            "GNU grep: " + grepLines.get(i)
                    );
                    break;
                }
            }

            if (asmLines.size() != grepLines.size()) {
                System.out.println(
                        "Output size mismatch: asmgrep="
                        + asmLines.size()
                        + ", grep="
                        + grepLines.size()
                );
            }

            if (!asm.stderr().isBlank()) {
                System.out.println(
                        "asmgrep stderr: " + asm.stderr()
                );
            }

            if (!grep.stderr().isBlank()) {
                System.out.println(
                        "GNU grep stderr: " + grep.stderr()
                );
            }
        }
    }

    private static Path generateTree(Path temp) throws IOException {
        Path root = temp.resolve("tree");
        Files.createDirectories(root);

        System.out.printf(
                "Generating %,d files in %d directories...%n",
                FILE_COUNT,
                DIRECTORY_COUNT
        );

        long start = System.nanoTime();

        for (int i = 0; i < FILE_COUNT; i++) {
            Path directory = root.resolve(
                    String.format("dir%03d", i % DIRECTORY_COUNT)
            );

            Files.createDirectories(directory);

            StringBuilder content = new StringBuilder();
            content.append("record ").append(i).append('\n');

            if (i % 97 == 0) {
                content.append("needle match ")
                        .append(i)
                        .append('\n');
            }

            content.append("footer ").append(i).append('\n');

            Path file = directory.resolve(
                    String.format("file%05d.txt", i)
            );

            Files.writeString(
                    file,
                    content,
                    StandardCharsets.UTF_8
            );
        }

        double seconds =
                (System.nanoTime() - start) / 1_000_000_000.0;

        System.out.printf(
                "Generated %,d files in %.3f seconds.%n",
                FILE_COUNT,
                seconds
        );

        return root;
    }

    public static void main(String[] args) throws Exception {

        if (!Files.isExecutable(ASM)) {
            throw new IllegalStateException(
                    "asmgrep binary not found or not executable: " + ASM
            );
        }

        if (!Files.isExecutable(GREP)) {
            throw new IllegalStateException(
                    "GNU grep not found at: " + GREP
            );
        }

        Path temp = Files.createTempDirectory("asmgrep-java-10k-");

        System.out.println("Temporary directory: " + temp);

        Path root = generateTree(temp);

        test("TEST 1 — RECURSIVE SEARCH (-r)",
                "-r", root, temp);

        test("TEST 2 — LINE NUMBERS (-rn)",
                "-rn", root, temp);

        test("TEST 3 — FILE COUNTS (-rc)",
                "-rc", root, temp);

        System.out.println("\n===== FINAL SUMMARY =====");
        System.out.println("Passed: " + passed + "/3");
        System.out.println("Failed: " + failed + "/3");
        System.out.println("Test tree: " + root);

        if (failed != 0) {
            throw new AssertionError(
                    failed + " stress test(s) failed."
            );
        }

        System.out.println("ALL 10K STRESS TESTS PASSED.");
    }
}
