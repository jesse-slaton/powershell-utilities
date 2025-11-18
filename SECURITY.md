# Security Policy

## Supported Versions

We release security updates for the following versions:

| Version | Supported          |
| ------- | ------------------ |
| main branch | :white_check_mark: |
| Earlier commits | :x:                |

**Note**: This repository is under active development and reorganization. Security fixes are applied to the main branch only.

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue in any PowerShell utilities in this repository, please report it responsibly.

### How to Report

**Please DO NOT report security vulnerabilities through public GitHub issues.**

Instead, please report security vulnerabilities by:

1. **Using GitHub Security Advisories** (preferred)
   - Go to the [Security tab](https://github.com/jesse-slaton/powershell-utilities/security/advisories)
   - Click "Report a vulnerability"
   - Fill out the form with details

2. **Email** (alternative)
   - Send an email to the repository maintainer
   - Include "SECURITY - PowerShell Utilities" in the subject line
   - Provide detailed information about the vulnerability

### What to Include

When reporting a vulnerability, please include:

- **Script Name**: Which script(s) are affected
- **Description**: A clear description of the vulnerability
- **Impact**: What an attacker could do with this vulnerability
- **Attack Scenario**: How the vulnerability could be exploited
- **Steps to Reproduce**: Detailed steps to reproduce the issue
- **Suggested Fix**: If you have ideas for a fix (optional)
- **Proof of Concept**: Code that demonstrates the issue (if applicable)

### What to Expect

- **Acknowledgment**: We will acknowledge receipt of your report within 48 hours
- **Updates**: We will provide regular updates on our progress (at least every 7 days)
- **Timeline**: We aim to release a fix within 90 days for critical vulnerabilities
- **Credit**: We will credit you in the security advisory (unless you prefer to remain anonymous)

### Safe Harbor

We support safe harbor for security researchers who:

- Make a good faith effort to avoid privacy violations, data destruction, and service interruption
- Only test against your own systems or with explicit permission
- Do not exploit the vulnerability beyond the minimum necessary to demonstrate the issue
- Report vulnerabilities promptly
- Keep the vulnerability confidential until it has been resolved

We will not pursue legal action against researchers who follow these guidelines.

## Security Considerations

### PowerShell Script Execution

These utilities interact with Windows systems in privileged ways:

#### Active Directory Scripts
- Query user and computer objects
- Access group membership and organizational data
- May expose sensitive corporate directory information
- **Risk**: Credential theft, information disclosure

#### File System Operations
- Modify files and directories
- May require elevated privileges
- Access user profiles and system directories
- **Risk**: Data loss, unauthorized access, privilege escalation

#### Service Management
- Start, stop, and configure Windows services
- Modify scheduled tasks
- **Risk**: Service disruption, persistence mechanisms

#### Registry Operations
- Read and write registry keys
- Modify system configuration
- **Risk**: System instability, privilege escalation

### Key Security Concerns

1. **Execution Policy Bypass**
   - Scripts may be run with bypassed execution policies
   - Always verify script source and integrity
   - Use code signing for production deployments

2. **Credential Handling**
   - Never hardcode credentials in scripts
   - Use Windows Credential Manager or secure vaults
   - Avoid passing credentials as plain text parameters

3. **Input Validation**
   - All scripts should validate input parameters
   - Sanitize inputs to prevent injection attacks
   - Use parameter validation attributes (`[ValidateNotNullOrEmpty()]`, etc.)

4. **Logging and Auditing**
   - Script execution should be logged
   - Sensitive operations should be auditable
   - Avoid logging credentials or sensitive data

5. **Least Privilege**
   - Scripts should request minimum necessary permissions
   - Document required privilege levels in help
   - Use `-WhatIf` and `-Confirm` for destructive operations

## Known Security Limitations

- **Work in Progress**: Scripts are being refactored; not all may follow current security standards
- **No Code Signing**: Scripts are not currently code-signed
- **Limited Input Validation**: Some legacy scripts may have incomplete input validation
- **Documentation Gaps**: Security requirements may not be fully documented for all scripts

## Security Best Practices

When using PowerShell utilities from this repository:

1. **Verify Before Execution**
   - Review script source code before running
   - Understand what the script does
   - Check for recent security issues

2. **Test First**
   - Test scripts in non-production environments
   - Use `-WhatIf` parameter when available
   - Verify backups before making changes

3. **Restrict Access**
   - Store scripts in protected locations
   - Use NTFS permissions to control access
   - Consider code signing for enterprise deployment

4. **Monitor Execution**
   - Enable PowerShell logging (module, script block, transcription)
   - Review logs for suspicious activity
   - Use constrained language mode in untrusted environments

5. **Keep Updated**
   - Pull latest changes regularly
   - Review changelog for security fixes
   - Subscribe to security advisories

6. **Environment Isolation**
   - Use separate accounts for privileged operations
   - Avoid running scripts with domain admin credentials
   - Consider using Just-Enough-Administration (JEA)

## Common Vulnerability Types

Be especially cautious of:

- **Command Injection**: Unsanitized input passed to `Invoke-Expression` or similar
- **Path Traversal**: File operations with user-controlled paths
- **XXE/SSRF**: XML processing or web requests with untrusted input
- **Credential Exposure**: Credentials in logs, error messages, or script output
- **Privilege Escalation**: Scripts that can be modified by low-privileged users
- **Information Disclosure**: Excessive error messages or verbose output

## Disclosure Policy

- We follow a **coordinated disclosure** policy
- Security issues will be disclosed publicly after a fix is available
- We will publish a security advisory with details of the vulnerability and the fix
- Critical vulnerabilities will be fast-tracked for release

## Contributing Security Fixes

If you'd like to contribute a security fix:

1. Report the vulnerability first (as described above)
2. Wait for acknowledgment before submitting a PR
3. Submit the PR to a private branch if requested
4. Include security impact assessment in PR description
5. Follow the coding standards in `docs/DEV_ENVIRONMENT.md`

## Contact

For security-related questions that are not vulnerabilities, you can:

- Open a regular GitHub issue with the `security` label
- Use the Discussions tab for general security questions

Thank you for helping keep our scripts and users safe!
