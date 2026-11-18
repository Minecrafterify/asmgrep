
package com.asmgrep;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.FileStore;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.TimeUnit;

public final class RecursiveStress500k {

    private static final long FILE_COUNT = 500_000L;
    private static final int DIRECTORY_COUNT = 5_000;
    private static final int FILES_PER_DIRECTORY = 100;

    private static final long MATCH_INTERVAL = 1_000L;
    private static final String PATTERN = "needle";

    private static final long TIMEOUT_HOURS = 6;

    private static final long REQUIRED_SPACE =
            5L * 1024 * 1024 * 1024;

    private static final Path ASM =
            Path.of("./build/asmgrep").toAbsolutePath();

    private static final Path GREP =
            Path.of("/usr/bin/grep");

    private static long generated;

    private record Result(
            int exitCode,
            List<String> output,
            String stderr,
            double seconds
    ) {}

    private static void validate() {

        if (!Files.isExecutable(ASM)) {
            throw new IllegalStateException(
                    "asmgrep not found or not executable: " + ASM
            );
        }

        if (!Files.isExecutable(GREP)) {
            throw new IllegalStateException(
                    "GNU grep not found: " + GREP
            );
        }

        if ((long) DIRECTORY_COUNT * FILES_PER_DIRECTORY
                != FILE_COUNT) {
            throw new IllegalStateException(
                    "Directory layout does not equal target file count."
            );
        }
    }

    private static void dryRun() {

        System.out.println("===== 500K FILE RECURSIVE STRESS TEST =====");
        System.out.println("Target files: " + FILE_COUNT);
        System.out.println("Directories: " + DIRECTORY_COUNT);
        System.out.println("Files per directory: " + FILES_PER_DIRECTORY);

        System.out.println("Expected matching files: "
                + (FILE_COUNT / MATCH_INTERVAL));

        System.out.println();

        System.out.println("Approximate storage at 4 KiB/file:");
        System.out.printf(
                "%,d bytes (approximately %.2f GB)%n",
                FILE_COUNT * 4096L,
                FILE_COUNT * 4096L / 1_000_000_000.0
        );

        System.out.println();

        System.out.println("This is only a dry run.");
        System.out.println(
                "Use --run-500k /path/to/test/directory"
        );
        System.out.println("to begin actual file creation.");
    }

    private static Path prepareTarget(Path target)
            throws IOException {

        target = target.toAbsolutePath().normalize();

        if (target.getParent() == null) {
            throw new IOException(
                    "Filesystem root cannot be used as test directory."
            );
        }

        if (Files.exists(target)) {

            if (!Files.isDirectory(target)) {
                throw new IOException(
                        "Target is not a directory."
                );
            }

            try (var entries = Files.list(target)) {
                if (entries.findAny().isPresent()) {
                    throw new IOException(
                            "Target directory must be empty: " + target
                    );
                }
            }

        } else {
            Files.createDirectories(target);
        }

        FileStore store = Files.getFileStore(target);

        long usable = store.getUsableSpace();

        System.out.println("Filesystem: " + store);

        System.out.printf(
                "Available space: %.2f GB%n",
                usable / 1_000_000_000.0
        );

        System.out.printf(
                "Required safety margin: %.2f GB%n",
                REQUIRED_SPACE / 1_000_000_000.0
        );

        if (usable < REQUIRED_SPACE) {
            throw new IOException(
                    "Insufficient free space for this stress test."
            );
        }

        System.out.println("Target: " + target);

        return target;
    }

    private static void generate(Path root)
            throws IOException {

        System.out.println("\n===== GENERATING FILES =====");

        long start = System.nanoTime();

        for (int d = 0; d < DIRECTORY_COUNT; d++) {

            Path directory = root.resolve(
                    String.format("dir-%05d", d)
            );

            Files.createDirectories(directory);

            for (int f = 0; f < FILES_PER_DIRECTORY; f++) {

                long index =
                        (long) d * FILES_PER_DIRECTORY + f;

                String filename =
                        String.format("file-%03d.txt", f);

                Path file = directory.resolve(filename);

                String content;

                if (index % MATCH_INTERVAL == 0) {

                    content = "record " + index
                            + "\nneedle match " + index + "\n";

                } else {

                    content = "record " + index + "\n";
                }

                Files.writeString(
                        file,
                        content,
                        StandardCharsets.UTF_8
                );

                generated++;

                if (generated % 50_000L == 0) {

                    double elapsed =
                            (System.nanoTime() - start)
                                    / 1_000_000_000.0;

                    double rate = generated / elapsed;

                    System.out.printf(
                            "Generated %,d / %,d (%.2f%%) | "
                                    + "%.0f files/sec | %.1f minutes elapsed%n",
                            generated,
                            FILE_COUNT,
                            generated * 100.0 / FILE_COUNT,
                            rate,
                            elapsed / 60.0
                    );
                }
            }
        }

        double seconds =
                (System.nanoTime() - start)
                        / 1_000_000_000.0;

        System.out.printf(
                "\nGeneration complete: %,d files in %.2f minutes%n",
                generated,
                seconds / 60.0
        );
    }

    private static Result execute(
            List<String> command,
            Path stdout,
            Path stderr
    ) throws Exception {

        ProcessBuilder builder = new ProcessBuilder(command);

        builder.redirectOutput(stdout.toFile());
        builder.redirectError(stderr.toFile());

        long start = System.nanoTime();

        Process process = builder.start();

        boolean completed = process.waitFor(
                TIMEOUT_HOURS,
                TimeUnit.HOURS
        );

        double seconds =
                (System.nanoTime() - start)
                        / 1_000_000_000.0;

        if (!completed) {

            process.destroyForcibly();
            process.waitFor();

            throw new IOException(
                    "Search timed out: " + command
            );
        }

        return new Result(
                process.exitValue(),
                Files.readAllLines(stdout, StandardCharsets.UTF_8),
                Files.readString(stderr, StandardCharsets.UTF_8),
                seconds
        );
    }

    private static void compare(
            String label,
            String mode,
            Path root,
            Path work
    ) throws Exception {

        System.out.println("\n===== " + label + " =====");

        Path asmOut = work.resolve("asm.out");
        Path asmErr = work.resolve("asm.err");

        Path grepOut = work.resolve("grep.out");
        Path grepErr = work.resolve("grep.err");

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

        System.out.println("Running asmgrep...");

        Result asm = execute(
                asmCommand,
                asmOut,
                asmErr
        );

        System.out.println("Running GNU grep...");

        Result grep = execute(
                grepCommand,
                grepOut,
                grepErr
        );

        List<String> asmLines =
                new ArrayList<>(asm.output());

        List<String> grepLines =
                new ArrayList<>(grep.output());

        Collections.sort(asmLines);
        Collections.sort(grepLines);

        boolean success =
                asm.exitCode() == grep.exitCode()
                && asmLines.equals(grepLines);

        System.out.printf(
                "asmgrep: %.2fs | exit=%d | matches=%d%n",
                asm.seconds(),
                asm.exitCode(),
                asmLines.size()
        );

        System.out.printf(
                "GNU grep: %.2fs | exit=%d | matches=%d%n",
                grep.seconds(),
                grep.exitCode(),
                grepLines.size()
        );

        if (success) {

            System.out.println("RESULT: PASS");

        } else {

            System.out.println("RESULT: FAIL");

            System.out.println(
                    "asmgrep output lines: " + asmLines.size()
            );

            System.out.println(
                    "GNU grep output lines: " + grepLines.size()
            );

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

            throw new AssertionError(
                    "Differential test failed: " + label
            );
        }
    }

    public static void main(String[] args)
            throws Exception {

        if (args.length == 0) {
            dryRun();
            return;
        }

        if (args.length != 2
                || !args[0].equals("--run-500k")) {

            System.out.println(
                    "Usage: java -cp tests/java "
                            + "com.asmgrep.RecursiveStress1B "
                            + "--run-500k /path/to/test/directory"
            );

            return;
        }

        validate();

        Path root = prepareTarget(Path.of(args[1]));

        Path work = Files.createTempDirectory(
                "asmgrep-500k-results-"
        );

        System.out.println(
                "\nWARNING: Creating 500,000 files."
        );

        System.out.println(
                "Generated files will remain in the target directory."
        );

        generate(root);

        System.out.println("\n===== DIFFERENTIAL TESTS =====");

        compare(
                "TEST 1 — RECURSIVE SEARCH (-r)",
                "-r",
                root,
                work
        );

        compare(
                "TEST 2 — LINE NUMBERS (-rn)",
                "-rn",
                root,
                work
        );

        System.out.println("\n===== FINAL SUMMARY =====");

        System.out.println("Files generated: " + generated);
        System.out.println("Tests passed: 2/2");
        System.out.println("Test directory: " + root);
        System.out.println("Result files: " + work);

        System.out.println(
                "\nALL 500K-FILE STRESS TESTS PASSED."
        );
    }
}
