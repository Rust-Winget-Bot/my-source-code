# This script runs on an ubuntu server, which has the following bootstrap script
#
# apt-get update
# apt-get install -qq wget apt-transport-https software-properties-common
# wget -q "https://packages.microsoft.com/config/ubuntu/$(lsb_release -rs)/packages-microsoft-prod.deb"
# dpkg -i packages-microsoft-prod.deb
# type -p curl >/dev/null || sudo apt install curl -y
# curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
# chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
# echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
# apt-get update
# apt-get install -qq powershell git gh
# rm packages-microsoft-prod.deb
# wget -q "https://raw.githubusercontent.com/Rust-Winget-Bot/my-source-code/main/check.ps1"
# $(which pwsh) -File "check.ps1"

Install-Module -Name powershell-yaml
Import-Module powershell-yaml
gh auth setup-git
gh repo clone "Rust-Winget-Bot/winget-pkgs"
cd winget-pkgs
git pull upstream master
git push
$lastFewVersions = git ls-remote --sort=-v:refname --tags https://github.com/rust-lang/rust.git | Foreach {(($_ -split '\t')[1]).Substring(10)} | Where-Object {!$_.Contains('release') -and !$_.Contains('^')} | Select -First 3;
$myPrs = gh pr list --author "Rust-Winget-Bot" --repo "microsoft/winget-pkgs" --state=all | Foreach {((($_ -split '\t')[2]) -split ':')[1]};
foreach ($toolchain in @("MSVC", "GNU")) {
    $toolchainLower = $toolchain.ToLower();
    $publishedVersions = winget show --id Rustlang.Rust.$toolchain --versions | Select -Skip 4 -First 5;
    foreach ($version in $lastFewVersions) {
        if ($publishedVersions.Contains($version)) {
            continue;
        } else {
            if ($myPrs -and $myPrs.Contains("rust-$version-$toolchainLower")) {
                continue;
            }
            git checkout master;
            git checkout -b rust-$version-$toolchainLower;
            $yamlPath = "manifests/r/Rustlang/Rust/$toolchain/$version/Rustlang.Rust.$toolchain.installer.yaml";
            $yamlObject = New-Object –TypeNamePSObject;
            $yamlObject | Add-Member -Name PackageIdentifier -Value "Rustlang.Rust.$toolchain"
            $yamlObject | Add-Member -Name PackageVersion -Value $version
            $yamlObject | Add-Member -Name MinimumOSVersion -Value "10.0.0.0"
            $yamlObject | Add-Member -Name InstallerType -Value wix
            $yamlObject | Add-Member -Name UpgradeBehavior -Value uninstallPrevious
            $yamlObject | Add-Member -Name ManifestType -Value installer
            $yamlObject | Add-Member -Name ManifestVersion -Value "1.2.0"
             if ($toolchain -eq "MSVC") {
                $installers = @("https://static.rust-lang.org/dist/rust-$version-aarch64-pc-windows-msvc.msi", "https://static.rust-lang.org/dist/rust-$version-i686-pc-windows-msvc.msi", "https://static.rust-lang.org/dist/rust-$version-x86_64-pc-windows-msvc.msi")
            } else {
                $installers = @("https://static.rust-lang.org/dist/rust-$version-i686-pc-windows-gnu.msi", "https://static.rust-lang.org/dist/rust-$version-x86_64-pc-windows-gnu.msi")
            }
            $yamlObject | Add-Member -Name Installers -Value @()
            $webClient = (new-object System.Net.WebClient);
            foreach ($installer in $installers) {
                $path = $installer.Substring($installer.LastIndexOf('/') + 1);
                $webClient.DownloadFile($installer, $path)
                $sha256 = (Get-FileHash $path -Algorithm SHA256).Hash;
                Remove-Item $path;
                $webClient.DownloadFile($installer, $path)
                $sha256_2 = (Get-FileHash $path -Algorithm SHA256).Hash;
                Remove-Item $path;
                if (-not($sha256 -eq $sha256_2)) {
                    throw "Sha256 returned two different results, shutting down to lack of confidence in sha value"
                }
                $productCode = "";
                $arch = if ($installer.Contains("i686")) {
                    if ($toolchain -eq "MSVC") {
                        $productCode = "{FBAC7273-35AB-4942-8B6A-A3407C4558C2}"
                    } elseif ($toolchain -eq "GNU") {
                        $productCode = "{4120AD8B-3C6B-4EBD-9646-DF20F3120208}"
                    }
                    "x86"
                } elseif ($installer.Contains("x86_64")) {
                    if ($toolchain -eq "MSVC") {
                        $productCode = "{F89628A9-D84F-486B-83F5-092007FA03C9}"
                    } elseif ($toolchain -eq "GNU") {
                        $productCode = "{C228EF57-CC84-4973-A41B-60C8861E51FF}"
                    }
                    "x64"
                } elseif ($installer.Contains("aarch64")) {
                    if ($toolchain -eq "MSVC") {
                        $productCode = "{4205D4CC-DCFE-4A97-9B95-E9B46D3FED71}"
                    } elseif ($toolchain -eq "GNU") {
                        # Nothing to do, arm64 gnu doesn't exist.
                    }
                    "arm64"
                }
                $bits = if ($arch -eq "x86") {
                    "32-bit"
                } elseif ($arch -eq "x64") {
                    "64-bit"
                } elseif ($arch -eq "arm64") {
                    "arm64"
                };
                $installerEntry = New-Object –TypeNamePSObject;
                $appsAndFeaturesEntry = New-Object –TypeNamePSObject;
                $appsAndFeaturesEntry | Add-Member -Name ProductCode -Value $productCode
                $appsAndFeaturesEntry | Add-Member -Name DisplayName -Value "Rust $version ($toolchain $bits)";
                $appsAndFeaturesEntry | Add-Member -Name DisplayVersion -Value "$version.0"
                $installerEntry | Add-Member -Name Architecture -Value $arch
                $installerEntry | Add-Member -Name InstallerUrl -Value $installer
                $installerEntry | Add-Member -Name InstallerSha256 -Value $sha256
                $installerEntry | Add-Member -Name AppsAndFeaturesEntries -Value @($appsAndFeaturesEntry);
                $yamlObject.Installers.Add($installerEntry)
            }
            $newYamlData = ConvertTo-YAML $yamlObject;
            Set-Content -Path $yamlPath -Value $newYamlData;
            $yamlPath = "manifests/r/Rustlang/Rust/$toolchain/$version/Rustlang.Rust.$toolchain.locale.en-US.yaml";
            $yamlObject = New-Object –TypeNamePSObject;
            $yamlObject | Add-Member -Name PackageIdentifier -Value "Rustlang.Rust.$toolchain"
            $yamlObject | Add-Member -Name PackageVersion -Value $version
            $yamlObject | Add-Member -Name PackageLocale -Value "en-US"
            $yamlObject | Add-Member -Name Publisher -Value "The Rust Project Developers"
            $yamlObject | Add-Member -Name PackageName -Value "Rust ($toolchain)"
            $yamlObject | Add-Member -Name PackageUrl -Value "https://www.rust-lang.org/"
            $yamlObject | Add-Member -Name License -Value "Apache 2.0 and MIT"
            $yamlObject | Add-Member -Name LicenseUrl -Value "https://raw.githubusercontent.com/rust-lang/rust/master/COPYRIGHT"
            $yamlObject | Add-Member -Name ShortDescription -Value "this is the rust-lang built with $toolchainLower toolchain"
            $yamlObject | Add-Member -Name Moniker -Value "rust-$toolchainLower"
            $yamlObject | Add-Member -Name ManifestType -Value "defaultLocale"
            $yamlObject | Add-Member -Name ManifestVersion -Value "1.2.0"
            $yamlObject | Add-Member -Name Tags -Value @($toolchainLower, "rust", "windows")
            $newYamlData = ConvertTo-YAML $yamlObject;
            Set-Content -Path $yamlPath -Value $newYamlData;
            $yamlPath = "manifests/r/Rustlang/Rust/$toolchain/$version/Rustlang.Rust.$toolchain.yaml";
            $yamlObject = New-Object –TypeNamePSObject;
            $yamlObject | Add-Member -Name PackageIdentifier -Value "Rustlang.Rust.$toolchain"
            $yamlObject | Add-Member -Name PackageVersion -Value $version
            $yamlObject | Add-Member -Name DefaultLocale -Value "en-US"
            $yamlObject | Add-Member -Name ManifestType -Value "version"
            $yamlObject | Add-Member -Name ManifestVersion -Value "1.2.0"
            $newYamlData = ConvertTo-YAML $yamlObject;
            Set-Content -Path $yamlPath -Value $newYamlData;
            git add --all .
            git commit -m"add Rustlang.Rust.$toolchain version $version"
            git push -u origin rust-$version-$toolchainLower;
            # Uncomment this once we've seen it work a few times and are happy with it.
            # gh pr create --title "add Rustlang.Rust.$toolchain version $version" --body "I'm a bot and this PR was opened automatically. If there's something wrong, please file an issue at https://github.com/Rust-Winget-Bot/bot-issues/issues"
        }
    }
}
