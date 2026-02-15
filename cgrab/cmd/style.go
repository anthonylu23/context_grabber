package cmd

import "github.com/spf13/cobra"

const styledUsageTemplate = `{{if .Long}}{{.Long}}

{{end}}Usage:
  {{.UseLine}}
{{if .Aliases}}
Aliases:
  {{.NameAndAliases}}
{{end}}{{if .HasAvailableSubCommands}}
Commands:
{{range .Commands}}{{if (or .IsAvailableCommand (eq .Name "help"))}}  {{rpad .Name .NamePadding }} {{.Short}}
{{end}}{{end}}{{end}}{{if .HasAvailableLocalFlags}}
Flags:
{{.LocalFlags.FlagUsages | trimTrailingWhitespaces}}
{{end}}{{if .HasAvailableInheritedFlags}}
Global Flags:
{{.InheritedFlags.FlagUsages | trimTrailingWhitespaces}}
{{end}}{{if .HasHelpSubCommands}}
Additional Help:
{{range .Commands}}{{if .IsAdditionalHelpTopicCommand}}  {{rpad .CommandPath .CommandPathPadding }} {{.Short}}
{{end}}{{end}}{{end}}
`

func applyCommandStyle(command *cobra.Command) {
	command.SetUsageTemplate(styledUsageTemplate)
	command.SetHelpTemplate(styledUsageTemplate)
	for _, child := range command.Commands() {
		applyCommandStyle(child)
	}
}
