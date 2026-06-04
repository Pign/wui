package wui.macros;

#if macro
import haxe.macro.Context;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
import haxe.Json;
#end

/**
 * Generates the MSBuild project files needed for a C++/WinRT WinUI 3 app:
 * - .vcxproj
 * - packages.config
 * - pch.h / pch.cpp
 * - app.manifest
 */
class ProjectGenerator {
    #if macro

    static inline var DEFAULT_SDK_VERSION = "1.5.240627000";

    /** Write file only if content has changed (avoids locking issues with MSBuild). */
    public static function writeIfChanged(path:String, content:String):Void {
        if (FileSystem.exists(path)) {
            var existing = File.getContent(path);
            if (existing == content) return;
        }
        try {
            File.saveContent(path, content);
        } catch (e:Dynamic) {
            // File may be locked by MSBuild — skip if unchanged write fails
            Sys.println('[wui] Warning: Could not write $path (file may be locked)');
        }
    }

    /**
     * Read the concrete Windows App SDK version from wui.json in the current
     * working directory. The .vcxproj imports props/targets via paths that
     * include the version number, so wildcards (e.g. "1.8.*") cannot be used
     * here — NuGet would resolve them at restore time but the .vcxproj would
     * still reference the wildcard path literally and fail.
     */
    static function readSdkVersion():String {
        var wuiJsonPath = Path.join([Sys.getCwd(), "wui.json"]);
        if (!FileSystem.exists(wuiJsonPath)) return DEFAULT_SDK_VERSION;
        var config:Dynamic;
        try {
            config = Json.parse(File.getContent(wuiJsonPath));
        } catch (e:Dynamic) {
            Sys.println('[wui] Warning: wui.json is not valid JSON, falling back to SDK ${DEFAULT_SDK_VERSION}');
            return DEFAULT_SDK_VERSION;
        }
        var v:String = config.windowsAppSdkVersion;
        if (v == null || v.length == 0) return DEFAULT_SDK_VERSION;
        if (v.indexOf("*") >= 0) {
            Sys.println('[wui] Warning: windowsAppSdkVersion "$v" contains a wildcard. The .vcxproj needs a concrete version (e.g. "1.5.240627000"). Falling back to ${DEFAULT_SDK_VERSION}.');
            return DEFAULT_SDK_VERSION;
        }
        return v;
    }

    /** Resolve the hxcpp library include directory by shelling out to
        `haxelib path hxcpp`. Needed by the .vcxproj so MainWindow.cpp
        can `#include <wui/generated/Callbacks.h>` and reach into the
        hxcpp-generated Haxe classes for click-handler bridges. */
    static function readHxcppIncludePath():String {
        var p:sys.io.Process = null;
        try {
            p = new sys.io.Process("haxelib", ["path", "hxcpp"]);
            var firstLine = StringTools.trim(p.stdout.readLine());
            p.close();
            // haxelib path emits the lib dir with a trailing slash on the
            // first line, then "-D hxcpp=<version>" on the next.
            if (firstLine.length > 0) {
                if (!StringTools.endsWith(firstLine, "/") && !StringTools.endsWith(firstLine, "\\")) {
                    firstLine += "/";
                }
                return firstLine + "include";
            }
        } catch (e:Dynamic) {
            if (p != null) try p.close() catch (_:Dynamic) {};
        }
        return "";
    }

    public static function generate(appName:String, outputDir:String):Void {
        if (!FileSystem.exists(outputDir)) {
            FileSystem.createDirectory(outputDir);
        }

        var sdkVersion = readSdkVersion();
        var hxcppInclude = readHxcppIncludePath();

        generateVcxproj(appName, outputDir, sdkVersion, hxcppInclude);
        generatePackagesConfig(outputDir, sdkVersion);
        generatePch(outputDir);
        generateAppManifest(appName, outputDir);
    }

    static function generateVcxproj(appName:String, outputDir:String, sdkVersion:String, hxcppInclude:String):Void {
        // Paths relative to the .vcxproj location (build/winui/)
        var cppDir = "..\\cpp";
        var packagesDir = "..\\packages";

        var content = '<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">

  <ItemGroup Label="ProjectConfigurations">
    <ProjectConfiguration Include="Debug|x64">
      <Configuration>Debug</Configuration>
      <Platform>x64</Platform>
    </ProjectConfiguration>
    <ProjectConfiguration Include="Release|x64">
      <Configuration>Release</Configuration>
      <Platform>x64</Platform>
    </ProjectConfiguration>
  </ItemGroup>

  <PropertyGroup Label="Globals">
    <VCProjectVersion>17.0</VCProjectVersion>
    <ProjectGuid>{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}</ProjectGuid>
    <RootNamespace>$appName</RootNamespace>
    <WindowsTargetPlatformVersion>10.0</WindowsTargetPlatformVersion>
    <WindowsAppSDKSelfContained>true</WindowsAppSDKSelfContained>
    <WindowsPackageType>None</WindowsPackageType>
    <AppxPackage>false</AppxPackage>
    <CppWinRTOptimized>true</CppWinRTOptimized>
    <CppWinRTRootNamespaceAutoMerge>true</CppWinRTRootNamespaceAutoMerge>
    <CppWinRTGenerateWindowsMetadata>false</CppWinRTGenerateWindowsMetadata>
  </PropertyGroup>

  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.Default.props" />

  <PropertyGroup Label="Configuration" Condition="\'$(Configuration)|$(Platform)\'==\'Debug|x64\'">
    <ConfigurationType>Application</ConfigurationType>
    <UseDebugLibraries>true</UseDebugLibraries>
    <PlatformToolset>v143</PlatformToolset>
    <CharacterSet>Unicode</CharacterSet>
  </PropertyGroup>

  <PropertyGroup Label="Configuration" Condition="\'$(Configuration)|$(Platform)\'==\'Release|x64\'">
    <ConfigurationType>Application</ConfigurationType>
    <UseDebugLibraries>false</UseDebugLibraries>
    <PlatformToolset>v143</PlatformToolset>
    <WholeProgramOptimization>true</WholeProgramOptimization>
    <CharacterSet>Unicode</CharacterSet>
  </PropertyGroup>

  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.props" />

  <!-- NuGet package props -->
  <Import Project="$packagesDir\\Microsoft.Windows.CppWinRT.2.0.240405.15\\build\\native\\Microsoft.Windows.CppWinRT.props" Condition="Exists(\'$packagesDir\\Microsoft.Windows.CppWinRT.2.0.240405.15\\build\\native\\Microsoft.Windows.CppWinRT.props\')" />
  <Import Project="$packagesDir\\Microsoft.WindowsAppSDK.${sdkVersion}\\build\\native\\Microsoft.WindowsAppSDK.props" Condition="Exists(\'$packagesDir\\Microsoft.WindowsAppSDK.${sdkVersion}\\build\\native\\Microsoft.WindowsAppSDK.props\')" />

  <ItemDefinitionGroup>
    <ClCompile>
      <PrecompiledHeader>Use</PrecompiledHeader>
      <PrecompiledHeaderFile>pch.h</PrecompiledHeaderFile>
      <AdditionalIncludeDirectories>$cppDir\\include;$hxcppInclude;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
      <LanguageStandard>stdcpp20</LanguageStandard>
      <ConformanceMode>true</ConformanceMode>
      <SDLCheck>true</SDLCheck>
      <!-- DISABLE_XAML_GENERATED_MAIN: we ship our own wWinMain.
           HX_*/HXCPP_*: hxcpp framework headers gate platform code on
           these. MainWindow.cpp includes <hxcpp.h> + the generated
           Callbacks header to dispatch `.onTap` handlers. -->
      <PreprocessorDefinitions>DISABLE_XAML_GENERATED_MAIN;HX_WINDOWS;HXCPP_M64;HXCPP_API_LEVEL=430;HX_SMART_STRINGS;HXCPP_VISIT_ALLOCS;STATIC_LINK;%(PreprocessorDefinitions)</PreprocessorDefinitions>
      <!-- Match hxcpp static_link CRT (it uses /MT release, /MTd debug).
           Mixing /MT and /MD across the lib boundary causes LNK2038. -->
      <RuntimeLibrary Condition="\'$(Configuration)\'==\'Debug\'">MultiThreadedDebug</RuntimeLibrary>
      <RuntimeLibrary Condition="\'$(Configuration)\'==\'Release\'">MultiThreaded</RuntimeLibrary>
      <!-- Force UTF-8 source encoding. Without /utf-8, MSVC reads the
           generated .cpp files as the system code page (CP-1252 on FR
           Windows) and L"..." literals containing non-ASCII chars get
           reinterpreted byte-per-byte as wide chars, producing mojibake. -->
      <AdditionalOptions>/utf-8 %(AdditionalOptions)</AdditionalOptions>
    </ClCompile>
    <Link>
      <SubSystem>Windows</SubSystem>
      <AdditionalLibraryDirectories>$cppDir;%(AdditionalLibraryDirectories)</AdditionalLibraryDirectories>
      <AdditionalDependencies>WindowsApp.lib;lib$appName.lib;%(AdditionalDependencies)</AdditionalDependencies>
      <DelayLoadDLLs>Microsoft.WindowsAppRuntime.Bootstrap.dll;%(DelayLoadDLLs)</DelayLoadDLLs>
    </Link>
  </ItemDefinitionGroup>

  <ItemGroup>
    <ClCompile Include="pch.cpp">
      <PrecompiledHeader>Create</PrecompiledHeader>
    </ClCompile>
    <ClCompile Include="App.cpp" />
    <ClCompile Include="MainWindow.cpp" />
  </ItemGroup>

  <ItemGroup>
    <ClInclude Include="pch.h" />
    <ClInclude Include="App.h" />
    <ClInclude Include="MainWindow.h" />
    <ClInclude Include="WuiRuntime.h" />
  </ItemGroup>

  <ItemGroup>
    <Manifest Include="app.manifest" />
  </ItemGroup>

  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.targets" />

  <!-- NuGet package targets -->
  <Import Project="$packagesDir\\Microsoft.Windows.CppWinRT.2.0.240405.15\\build\\native\\Microsoft.Windows.CppWinRT.targets" Condition="Exists(\'$packagesDir\\Microsoft.Windows.CppWinRT.2.0.240405.15\\build\\native\\Microsoft.Windows.CppWinRT.targets\')" />
  <Import Project="$packagesDir\\Microsoft.WindowsAppSDK.${sdkVersion}\\build\\native\\Microsoft.WindowsAppSDK.targets" Condition="Exists(\'$packagesDir\\Microsoft.WindowsAppSDK.${sdkVersion}\\build\\native\\Microsoft.WindowsAppSDK.targets\')" />
  <Import Project="$packagesDir\\Microsoft.Windows.SDK.BuildTools.10.0.22621.756\\build\\native\\Microsoft.Windows.SDK.BuildTools.targets" Condition="Exists(\'$packagesDir\\Microsoft.Windows.SDK.BuildTools.10.0.22621.756\\build\\native\\Microsoft.Windows.SDK.BuildTools.targets\')" />


</Project>
';
        writeIfChanged(Path.join([outputDir, '$appName.vcxproj']), content);
    }

    static function generatePackagesConfig(outputDir:String, sdkVersion:String):Void {
        var content = '<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="Microsoft.WindowsAppSDK" version="$sdkVersion" targetFramework="native" />
  <package id="Microsoft.Windows.CppWinRT" version="2.0.240405.15" targetFramework="native" />
  <package id="Microsoft.Windows.SDK.BuildTools" version="10.0.22621.756" targetFramework="native" />
  <package id="Microsoft.Windows.ImplementationLibrary" version="1.0.240122.1" targetFramework="native" />
</packages>
';
        writeIfChanged(Path.join([outputDir, "packages.config"]), content);
    }

    static function generatePch(outputDir:String):Void {
        var header = '#pragma once

// Windows headers
#include <unknwn.h>
#include <winrt/base.h>

// WinUI 3 / Windows App SDK
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Microsoft.UI.h>
#include <winrt/Microsoft.UI.Composition.h>
#include <winrt/Microsoft.UI.Dispatching.h>
#include <winrt/Microsoft.UI.Xaml.h>
#include <winrt/Microsoft.UI.Xaml.Controls.h>
#include <winrt/Microsoft.UI.Xaml.Controls.Primitives.h>
#include <winrt/Microsoft.UI.Xaml.Input.h>
#include <winrt/Microsoft.UI.Xaml.Media.h>
#include <winrt/Microsoft.UI.Xaml.Navigation.h>
#include <winrt/Microsoft.UI.Xaml.Markup.h>
#include <winrt/Microsoft.UI.Xaml.XamlTypeInfo.h>
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Windows.Graphics.h>
#include <winrt/Windows.UI.Xaml.Interop.h>

// Standard library
#include <string>
#include <functional>
#include <vector>
#include <memory>

// WuiRuntime
#include "WuiRuntime.h"
';
        writeIfChanged(Path.join([outputDir, "pch.h"]), header);

        var source = '#include "pch.h"\n';
        writeIfChanged(Path.join([outputDir, "pch.cpp"]), source);
    }

    static function generateAppManifest(appName:String, outputDir:String):Void {
        var content = '<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="$appName"/>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <!-- Windows 10/11 -->
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" />
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true</dpiAware>
    </windowsSettings>
  </application>
</assembly>
';
        writeIfChanged(Path.join([outputDir, "app.manifest"]), content);
    }
    #end
}
