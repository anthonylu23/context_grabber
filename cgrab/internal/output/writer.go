package output

import (
	"context"
	"fmt"
	"os"
	"os/exec"
)

func Write(ctx context.Context, payload []byte, outputFile string, clipboard bool) error {
	if outputFile != "" {
		if err := os.WriteFile(outputFile, payload, 0o644); err != nil {
			return fmt.Errorf("write output file: %w", err)
		}
	}

	if clipboard {
		if err := copyToClipboard(ctx, payload); err != nil {
			return err
		}
	}

	if outputFile == "" {
		if _, err := os.Stdout.Write(payload); err != nil {
			return fmt.Errorf("write stdout: %w", err)
		}
		if len(payload) == 0 || payload[len(payload)-1] != '\n' {
			if _, err := os.Stdout.Write([]byte("\n")); err != nil {
				return fmt.Errorf("write stdout newline: %w", err)
			}
		}
	}

	return nil
}

func copyToClipboard(ctx context.Context, payload []byte) error {
	cmd := exec.CommandContext(ctx, "pbcopy")
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("pbcopy stdin pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start pbcopy: %w", err)
	}

	if _, err := stdin.Write(payload); err != nil {
		_ = stdin.Close()
		return fmt.Errorf("write pbcopy stdin: %w", err)
	}
	if err := stdin.Close(); err != nil {
		return fmt.Errorf("close pbcopy stdin: %w", err)
	}
	if err := cmd.Wait(); err != nil {
		return fmt.Errorf("pbcopy wait: %w", err)
	}
	return nil
}
