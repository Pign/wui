package wui.macros;

#if macro
import haxe.macro.Context;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
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

    public static function generate(appName:String, outputDir:String):Void {
        if (!FileSystem.exists(outputDir)) {
            FileSystem.createDirectory(outputDir);
        }

        generateVcxproj(appName, outputDir);
        generatePackagesConfig(outputDir);
        generatePch(outputDir);
        generateAppManifest(appName, outputDir);
    }

    static function generateVcxproj(appName:String, outputDir:String):Void {
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
    <CppWinRTGenerateWindowsMetadata>true</CppWinRTGenerateWindowsMetadata>
    <EnableXbfGeneration>false</EnableXbfGeneration>
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
  <Import Project="$packagesDir\\Microsoft.WindowsAppSDK.1.5.240627000\\build\\native\\Microsoft.WindowsAppSDK.props" Condition="Exists(\'$packagesDir\\Microsoft.WindowsAppSDK.1.5.240627000\\build\\native\\Microsoft.WindowsAppSDK.props\')" />

  <ItemDefinitionGroup>
    <ClCompile>
      <PrecompiledHeader>Use</PrecompiledHeader>
      <PrecompiledHeaderFile>pch.h</PrecompiledHeaderFile>
      <AdditionalIncludeDirectories>$cppDir\\include;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
      <LanguageStandard>stdcpp20</LanguageStandard>
      <ConformanceMode>true</ConformanceMode>
      <SDLCheck>true</SDLCheck>
      <PreprocessorDefinitions>DISABLE_XAML_GENERATED_MAIN;%(PreprocessorDefinitions)</PreprocessorDefinitions>
    </ClCompile>
    <Link>
      <SubSystem>Windows</SubSystem>
      <AdditionalDependencies>WindowsApp.lib;%(AdditionalDependencies)</AdditionalDependencies>
      <DelayLoadDLLs>Microsoft.WindowsAppRuntime.Bootstrap.dll;%(DelayLoadDLLs)</DelayLoadDLLs>
      <!-- TODO: Add $cppDir\\lib${appName}.lib when linking hxcpp -->
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
    <Midl Include="App.idl" />
  </ItemGroup>

  <ItemGroup>
    <ApplicationDefinition Include="App.xaml">
      <SubType>Designer</SubType>
    </ApplicationDefinition>
  </ItemGroup>

  <ItemGroup>
    <Manifest Include="app.manifest" />
  </ItemGroup>

  <Import Project="$(VCTargetsPath)\\Microsoft.Cpp.targets" />

  <!-- NuGet package targets -->
  <Import Project="$packagesDir\\Microsoft.Windows.CppWinRT.2.0.240405.15\\build\\native\\Microsoft.Windows.CppWinRT.targets" Condition="Exists(\'$packagesDir\\Microsoft.Windows.CppWinRT.2.0.240405.15\\build\\native\\Microsoft.Windows.CppWinRT.targets\')" />
  <Import Project="$packagesDir\\Microsoft.WindowsAppSDK.1.5.240627000\\build\\native\\Microsoft.WindowsAppSDK.targets" Condition="Exists(\'$packagesDir\\Microsoft.WindowsAppSDK.1.5.240627000\\build\\native\\Microsoft.WindowsAppSDK.targets\')" />
  <Import Project="$packagesDir\\Microsoft.Windows.SDK.BuildTools.10.0.22621.756\\build\\native\\Microsoft.Windows.SDK.BuildTools.targets" Condition="Exists(\'$packagesDir\\Microsoft.Windows.SDK.BuildTools.10.0.22621.756\\build\\native\\Microsoft.Windows.SDK.BuildTools.targets\')" />

  <!-- Override: skip XBF copy (App.xaml is resource-loading only, no compiled XAML needed) -->
  <Target Name="CopyGeneratedXaml" />

  <!-- Override MRT targets that fail looking for App.xbf -->
  <Target Name="_GenerateProjectPriConfigurationFiles" />
  <Target Name="_GenerateProjectPriFileCore" />

</Project>
';
        writeIfChanged(Path.join([outputDir, '$appName.vcxproj']), content);
    }

    static function generatePackagesConfig(outputDir:String):Void {
        var content = '<?xml version="1.0" encoding="utf-8"?>
<packages>
  <package id="Microsoft.WindowsAppSDK" version="1.5.240627000" targetFramework="native" />
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
#include <winrt/Microsoft.UI.Windowing.h>
#include <winrt/Windows.Graphics.h>

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
