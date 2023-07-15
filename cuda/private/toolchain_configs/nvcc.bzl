load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")
load("//cuda/private:action_names.bzl", "ACTION_NAMES")
load("//cuda/private:artifact_categories.bzl", "ARTIFACT_CATEGORIES")
load("//cuda/private:providers.bzl", "CudaToolchainConfigInfo", "CudaToolkitInfo")
load("//cuda/private:toolchain_configs/utils.bzl", "nvcc_version_ge")
load("//cuda/private:toolchain.bzl", "use_cpp_toolchain")
load(
    "//cuda/private:toolchain_config_lib.bzl",
    "action_config",
    "artifact_name_pattern",
    "env_entry",
    "env_set",
    "feature",
    "flag_group",
    "flag_set",
)

def _impl(ctx):
    artifact_name_patterns = [
        # artifact_name_pattern for object files
        artifact_name_pattern(
            category_name = ARTIFACT_CATEGORIES.object_file,
            prefix = "",
            extension = ".o",
        ),
        artifact_name_pattern(
            category_name = ARTIFACT_CATEGORIES.pic_object_file,
            prefix = "",
            extension = ".pic.o",
        ),
        artifact_name_pattern(
            category_name = ARTIFACT_CATEGORIES.rdc_object_file,
            prefix = "",
            extension = ".rdc.o",
        ),
        artifact_name_pattern(
            category_name = ARTIFACT_CATEGORIES.rdc_pic_object_file,
            prefix = "",
            extension = ".rdc.pic.o",
        ),
    ]

    cc_toolchain = find_cpp_toolchain(ctx)

    compiler_param_file = feature(name = "compiler_param_file")

    nvcc_compile_env_feature = feature(
        name = "nvcc_compile_env",
        env_sets = [
            env_set(
                actions = [ACTION_NAMES.cuda_compile],
                env_entries = [env_entry("PATH", paths.dirname(cc_toolchain.compiler_executable))],
            ),
        ],
    )

    nvcc_device_link_env_feature = feature(
        name = "nvcc_device_link_env",
        env_sets = [
            env_set(
                actions = [ACTION_NAMES.device_link],
                env_entries = [env_entry("PATH", paths.dirname(cc_toolchain.compiler_executable))],
            ),
        ],
    )

    host_compiler_feature = feature(
        name = "host_compiler_path",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                    ACTION_NAMES.device_link,
                ],
                flag_groups = [flag_group(flags = ["-ccbin", "%{host_compiler}"])],
            ),
        ],
    )

    cuda_compile_action = action_config(
        action_name = ACTION_NAMES.cuda_compile,
        flag_sets = [
            flag_set(flag_groups = [
                flag_group(flags = ["-x", "cu"]),
                flag_group(
                    iterate_over = "arch_specs",
                    flag_groups = [
                        flag_group(
                            iterate_over = "arch_specs.stage2_archs",
                            flag_groups = [
                                flag_group(
                                    expand_if_true = "arch_specs.stage2_archs.virtual",
                                    flags = ["-gencode", "arch=compute_%{arch_specs.stage1_arch},code=compute_%{arch_specs.stage2_archs.arch}"],
                                ),
                                flag_group(
                                    expand_if_true = "arch_specs.stage2_archs.gpu",
                                    flags = ["-gencode", "arch=compute_%{arch_specs.stage1_arch},code=sm_%{arch_specs.stage2_archs.arch}"],
                                ),
                                flag_group(
                                    expand_if_true = "arch_specs.stage2_archs.lto",
                                    flags = ["-gencode", "arch=compute_%{arch_specs.stage1_arch},code=lto_%{arch_specs.stage2_archs.arch}"],
                                ),
                            ],
                        ),
                    ],
                ),
                flag_group(flags = ["-rdc=true"], expand_if_true = "use_rdc"),
            ]),
        ],
        implies = [
            "host_compiler_path",
            "include_paths",
            "defines",
            "host_defines",
            "compiler_input_flags",
            "compiler_output_flags",
            "nvcc_compile_env",
        ],
    )

    supports_compiler_device_link_feature = feature(name = "supports_compiler_device_link")

    cuda_device_link_action = action_config(
        action_name = ACTION_NAMES.device_link,
        flag_sets = [
            flag_set(flag_groups = [
                flag_group(flags = ["-dlink"]),
                flag_group(
                    iterate_over = "arch_specs",
                    flag_groups = [
                        flag_group(
                            iterate_over = "arch_specs.stage2_archs",
                            flag_groups = [
                                flag_group(
                                    expand_if_true = "arch_specs.stage2_archs.virtual",
                                    flags = ["-gencode", "arch=compute_%{arch_specs.stage1_arch},code=compute_%{arch_specs.stage2_archs.arch}"],
                                ),
                                flag_group(
                                    expand_if_true = "arch_specs.stage2_archs.gpu",
                                    flags = ["-gencode", "arch=compute_%{arch_specs.stage1_arch},code=sm_%{arch_specs.stage2_archs.arch}"],
                                ),
                                flag_group(
                                    expand_if_true = "arch_specs.stage2_archs.lto",
                                    flags = ["-gencode", "arch=compute_%{arch_specs.stage1_arch},code=sm_%{arch_specs.stage2_archs.arch}"],
                                ),
                            ],
                        ),
                    ],
                ),
                flag_group(flags = ["-dlto"], expand_if_true = "use_dlto"),
            ]),
        ],
        implies = [
            "host_compiler_path",
            # "linker_input_flags",
            "compiler_output_flags",
            "nvcc_device_link_env",
            "supports_compiler_device_link",
        ],
    )

    arch_native_feature = feature(
        name = "arch_native",
        enabled = False,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                    ACTION_NAMES.device_link,
                ],
                flag_groups = [
                    flag_group(
                        expand_if_true = "use_arch_native",
                        flags = ["-arch=native"],
                    ),
                ],
            ),
        ],
    )

    pic_feature = feature(
        name = "pic",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                    ACTION_NAMES.device_link,
                ],
                flag_groups = [
                    flag_group(flags = ["-Xcompiler", "-fPIC"], expand_if_true = "use_pic"),
                ],
            ),
        ],
    )

    include_paths_feature = feature(
        name = "include_paths",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = ["-I", "%{quote_include_paths}"],
                        iterate_over = "quote_include_paths",
                    ),
                    flag_group(
                        flags = ["-I", "%{include_paths}"],
                        iterate_over = "include_paths",
                    ),
                    flag_group(
                        flags = ["-isystem", "%{system_include_paths}"],
                        iterate_over = "system_include_paths",
                    ),
                ],
            ),
        ],
    )

    defines_feature = feature(
        name = "defines",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = ["-D%{defines}"],
                        iterate_over = "defines",
                    ),
                ],
            ),
        ],
    )

    host_defines_feature = feature(
        name = "host_defines",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = ["-D%{host_defines}"],
                        iterate_over = "host_defines",
                    ),
                ],
            ),
        ],
    )

    compile_flags_feature = feature(
        name = "compile_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = ["%{compile_flags}"],
                        iterate_over = "compile_flags",
                    ),
                ],
            ),
        ],
    )

    host_compile_flags_feature = feature(
        name = "host_compile_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                    ACTION_NAMES.device_link,
                ],
                flag_groups = [
                    flag_group(
                        flags = ["-Xcompiler", "%{host_compile_flags}"],
                        iterate_over = "host_compile_flags",
                    ),
                ],
            ),
        ],
    )

    dbg_feature = feature(
        name = "dbg",
        flag_sets = [
            flag_set(
                actions = [ACTION_NAMES.cuda_compile],
                flag_groups = [flag_group(flags = ["-O0", "-g"])],
            ),
        ],
        provides = ["compilation_mode"],
    )

    opt_feature = feature(
        name = "opt",
        flag_sets = [
            flag_set(
                actions = [ACTION_NAMES.cuda_compile],
                flag_groups = [flag_group(flags = [
                    "--dopt",  # the default depends on the value of --device-debug (-G), so set it explicitly.
                    "on",
                    "-Xcompiler",
                    "-g0",
                    "-O2",
                    "-DNDEBUG",
                    "-Xcompiler",
                    "-ffunction-sections",
                    "-Xcompiler",
                    "-fdata-sections",
                ])],
            ),
        ],
        provides = ["compilation_mode"],
    )

    fastbuild_feature = feature(
        name = "fastbuild",
        flag_sets = [
            flag_set(
                actions = [ACTION_NAMES.cuda_compile],
                flag_groups = [flag_group(flags = ["-O0", "--generate-line-info", "-Xcompiler", "-g1"])],
            ),
        ],
        provides = ["compilation_mode"],
    )

    ptxas_flags_feature = feature(
        name = "ptxas_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                ],
                flag_groups = [
                    flag_group(
                        flags = ["-Xptxas", "%{ptxas_flags}"],
                        iterate_over = "ptxas_flags",
                    ),
                ],
            ),
        ],
    )

    compiler_input_flags_feature = feature(
        name = "compiler_input_flags",
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                ],
                flag_groups = [flag_group(flags = ["-c", "%{source_file}"])],
            ),
        ],
    )

    compiler_output_flags_feature = feature(
        name = "compiler_output_flags",
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                    ACTION_NAMES.device_link,
                ],
                flag_groups = [flag_group(flags = ["-o", "%{output_file}"])],
            ),
        ],
    )

    nvcc_allow_unsupported_compiler_feature = feature(
        name = "nvcc_allow_unsupported_compiler",
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                    ACTION_NAMES.device_link,
                ],
                flag_groups = [flag_group(flags = ["--allow-unsupported-compiler"])],
            ),
        ],
    )

    nvcc_relaxed_constexpr_feature = feature(
        name = "nvcc_relaxed_constexpr",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                    ACTION_NAMES.device_link,
                ],
                flag_groups = [flag_group(flags = ["--expt-relaxed-constexpr"])],
            ),
        ],
    )

    nvcc_extended_lambda_feature = feature(
        name = "nvcc_extended_lambda",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.cuda_compile,
                    ACTION_NAMES.device_link,
                ],
                flag_groups = [flag_group(flags = ["--extended-lambda" if nvcc_version_ge(ctx, 10, 2) else "--expt-extended-lambda"])],
            ),
        ],
    )

    cuda_device_debug_feature = feature(
        name = "cuda_device_debug",
        flag_sets = [
            flag_set(
                actions = [ACTION_NAMES.cuda_compile],
                flag_groups = [flag_group(flags = ["--device-debug"])],
            ),
        ],
    )

    action_configs = [
        cuda_compile_action,
        cuda_device_link_action,
    ]

    features = [
        compiler_param_file,
        nvcc_compile_env_feature,
        nvcc_device_link_env_feature,
        arch_native_feature,
        pic_feature,
        host_compiler_feature,
        supports_compiler_device_link_feature,
        include_paths_feature,
        defines_feature,
        host_defines_feature,
        compile_flags_feature,
        host_compile_flags_feature,
        dbg_feature,
        opt_feature,
        fastbuild_feature,
        ptxas_flags_feature,
        compiler_input_flags_feature,
        compiler_output_flags_feature,
        nvcc_allow_unsupported_compiler_feature,
        nvcc_relaxed_constexpr_feature,
        nvcc_extended_lambda_feature,
        cuda_device_debug_feature,
    ]

    return [CudaToolchainConfigInfo(
        action_configs = action_configs,
        features = features,
        artifact_name_patterns = artifact_name_patterns,
        toolchain_identifier = ctx.attr.toolchain_identifier,
        cuda_toolkit = ctx.attr.cuda_toolkit,
    )]

cuda_toolchain_config = rule(
    doc = """This rule provides the predefined cuda toolchain configuration for NVCC with non MSVC as host compiler.""",
    implementation = _impl,
    attrs = {
        "cuda_toolkit": attr.label(mandatory = True, providers = [CudaToolkitInfo], doc = "A target that provides a `CudaToolkitInfo`."),
        "toolchain_identifier": attr.string(values = ["nvcc"], mandatory = True),
        "nvcc_version_major": attr.int(doc = "The CUDA Toolkit major version, e.g, 11 for 11.6"),
        "nvcc_version_minor": attr.int(doc = "The CUDA Toolkit minor version, e.g, 6 for 11.6"),
        "_cc_toolchain": attr.label(default = "@bazel_tools//tools/cpp:current_cc_toolchain"),  # legacy behaviour
    },
    provides = [CudaToolchainConfigInfo],
    toolchains = use_cpp_toolchain(),
)
