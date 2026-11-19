<#
.SYNOPSIS
    Demo of a cross-platform Avalonia window from PowerShell 7 with a button that fills a text box.

.DESCRIPTION
    Builds a window from inline Avalonia XAML with one button ("My Button") and one text
    box, then shows it with Show-AvaloniaWindow. Clicking the button puts
    "Hello, World from <OS> running PowerShell Core <Version>" in the text box, using
    $PSVersionTable.OS and $PSVersionTable.PSVersion. Makes no changes and writes
    nothing to the pipeline.

.EXAMPLE
    .\test-UIforPS7.ps1

    Opens the demo window.

.NOTES
    Written for PowerShell 7 (in Windows PowerShell 5.1, $PSVersionTable.OS is empty).
    Requires a module that provides ConvertTo-AvaloniaWindow, Find-AvaloniaControl and
    Show-AvaloniaWindow (such as PSAvalonia), already imported or auto-loadable. Needs
    a desktop session.
#>

$Xaml = '<Window xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        mc:Ignorable="d" d:DesignWidth="800" d:DesignHeight="450"
        x:Class="avaloniaui.MainWindow"
        Title="avaloniaui">
   <StackPanel>
	<Button Width="160" Name="button">My Button</Button>
        <TextBox HorizontalAlignment="Left" Margin="12,12,0,0" Name="txtDemo" VerticalAlignment="Top" Width="500" Height="25" />
    </StackPanel>
</Window>'
$window = ConvertTo-AvaloniaWindow -Xaml $Xaml
$Button = Find-AvaloniaControl -Name 'button' -Window $Window
$txtDemo = Find-AvaloniaControl -Name 'txtDemo' -Window $Window
$Button.add_Click({$txtDemo.Text = "Hello, World from $($PSVersionTable.OS) running PowerShell Core $($PSVersionTable.PSVersion)"})
Show-AvaloniaWindow -Window $Window