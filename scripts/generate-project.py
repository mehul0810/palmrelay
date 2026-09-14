#!/usr/bin/env python3
"""Generate a dependency-free Xcode project. Run from any working directory."""
import hashlib
import pathlib
import plistlib

root = pathlib.Path(__file__).resolve().parents[1]
objects = {}

def uid(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def add(name, value):
    key = uid(name)
    objects[key] = value
    return key

def quote(value):
    return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'

def encode(value):
    if isinstance(value, dict):
        return '{\n' + '\n'.join(f'{quote(k)} = {encode(v)};' for k, v in value.items()) + '\n}'
    if isinstance(value, list):
        return '(' + ', '.join(encode(v) for v in value) + ')'
    return quote(value)

shared = sorted(root.glob('Sources/**/*.swift'))
products, targets, file_refs = [], [], []
for name, folder, platform, bundle in [
    ('PalmRelay', 'iOS', 'iphoneos', 'com.mehulgohil.palmrelay'),
    ('PalmRelayCompanion', 'Mac', 'macosx', 'com.mehulgohil.palmrelay.companion')
]:
    build_files = []
    for path in shared + sorted((root / 'Apps' / folder).glob('*.swift')):
        relative = str(path.relative_to(root))
        ref = add('file:' + relative, dict(isa='PBXFileReference', lastKnownFileType='sourcecode.swift', path=relative, sourceTree='<group>'))
        if ref not in file_refs:
            file_refs.append(ref)
        build_files.append(add(name + ':' + relative, dict(isa='PBXBuildFile', fileRef=ref)))
    sources = add(name + ':sources', dict(isa='PBXSourcesBuildPhase', buildActionMask='2147483647', files=build_files, runOnlyForDeploymentPostprocessing='0'))
    frameworks = add(name + ':frameworks', dict(isa='PBXFrameworksBuildPhase', buildActionMask='2147483647', files=[], runOnlyForDeploymentPostprocessing='0'))
    product = add(name + ':product', dict(isa='PBXFileReference', explicitFileType='wrapper.application', path=name + '.app', sourceTree='BUILT_PRODUCTS_DIR'))
    products.append(product)
    configurations = []
    for config in ['Debug', 'Release']:
        settings = dict(PRODUCT_NAME='$(TARGET_NAME)', PRODUCT_BUNDLE_IDENTIFIER=bundle, SDKROOT=platform,
                        SWIFT_VERSION='5.0', CODE_SIGN_STYLE='Automatic', GENERATE_INFOPLIST_FILE='NO',
                        INFOPLIST_FILE=f'Apps/{folder}/Info.plist', MARKETING_VERSION='0.1.0', CURRENT_PROJECT_VERSION='1',
                        SWIFT_OPTIMIZATION_LEVEL='-Onone' if config == 'Debug' else '-O',
                        SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG' if config == 'Debug' else '',
                        ENABLE_USER_SCRIPT_SANDBOXING='YES', CLANG_ENABLE_MODULES='YES')
        if platform == 'iphoneos':
            settings.update(IPHONEOS_DEPLOYMENT_TARGET='17.0', TARGETED_DEVICE_FAMILY='1,2', SUPPORTED_PLATFORMS='iphoneos iphonesimulator', SUPPORTS_MACCATALYST='NO')
        else:
            settings.update(MACOSX_DEPLOYMENT_TARGET='14.0', ENABLE_APP_SANDBOX='NO', ENABLE_HARDENED_RUNTIME='YES', COMBINE_HIDPI_IMAGES='YES')
        configurations.append(add(name + config, dict(isa='XCBuildConfiguration', name=config, buildSettings=settings)))
    config_list = add(name + ':configlist', dict(isa='XCConfigurationList', buildConfigurations=configurations, defaultConfigurationIsVisible='0', defaultConfigurationName='Release'))
    target = add(name + ':target', dict(isa='PBXNativeTarget', name=name, productName=name, productType='com.apple.product-type.application',
                                     productReference=product, buildConfigurationList=config_list, buildPhases=[sources, frameworks], buildRules=[], dependencies=[]))
    targets.append(target)
    info = dict(CFBundleDevelopmentRegion='en', CFBundleExecutable='$(EXECUTABLE_NAME)', CFBundleIdentifier='$(PRODUCT_BUNDLE_IDENTIFIER)',
                CFBundleInfoDictionaryVersion='6.0', CFBundleName='$(PRODUCT_NAME)', CFBundlePackageType='APPL',
                CFBundleShortVersionString='$(MARKETING_VERSION)', CFBundleVersion='$(CURRENT_PROJECT_VERSION)',
                NSLocalNetworkUsageDescription='PalmRelay discovers and securely connects your iPhone and Mac so you can control your desktop.',
                NSBonjourServices=['_palmrelay-v1._tcp', '_palmrelay-v1._udp'])
    if platform == 'iphoneos':
        info.update(UILaunchScreen={}, UIApplicationSceneManifest={'UIApplicationSupportsMultipleScenes': False},
                    UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'],
                    ITSAppUsesNonExemptEncryption=True)
    else:
        info.update(NSHighResolutionCapable=True, LSApplicationCategoryType='public.app-category.productivity')
    (root / 'Apps' / folder / 'Info.plist').write_bytes(plistlib.dumps(info))

product_group = add('products', dict(isa='PBXGroup', name='Products', children=products, sourceTree='<group>'))
main_group = add('main', dict(isa='PBXGroup', children=file_refs + [product_group], sourceTree='<group>'))
project_configs = [add('project:' + c, dict(isa='XCBuildConfiguration', name=c, buildSettings={})) for c in ['Debug', 'Release']]
project_config_list = add('project:configlist', dict(isa='XCConfigurationList', buildConfigurations=project_configs, defaultConfigurationIsVisible='0', defaultConfigurationName='Release'))
project = add('project', dict(isa='PBXProject', attributes={'LastUpgradeCheck': '2600'}, buildConfigurationList=project_config_list,
                            compatibilityVersion='Xcode 14.0', developmentRegion='en', knownRegions=['en', 'Base'], mainGroup=main_group,
                            productRefGroup=product_group, projectDirPath='', projectRoot='', targets=targets))
directory = root / 'PalmRelay.xcodeproj'
directory.mkdir(exist_ok=True)
(directory / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + encode(dict(archiveVersion='1', classes={}, objectVersion='56', objects=objects, rootObject=project)) + '\n')
schemes = directory / 'xcshareddata' / 'xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
for name in ['PalmRelay', 'PalmRelayCompanion']:
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(name + ":target")}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:PalmRelay.xcodeproj"/>'
    (schemes / (name + '.xcscheme')).write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated PalmRelay.xcodeproj (iOS + Mac companion).')
