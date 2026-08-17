use ash::vk;

/// Attempts to load the Vulkan loader, create a headless instance, and
/// enumerate physical devices. This is what DXVK (used by Proton/Wine) needs
/// to work at all - without a software rasterizer ICD (e.g. Mesa's lavapipe)
/// registered in a GPU-less container, this fails and every DXVK-based game
/// fails with it. Returns (passed, description).
pub fn check() -> (bool, String) {
    // SAFETY: dynamically loads the Vulkan loader (libvulkan.so.1 / vulkan-1.dll
    // / libvulkan.dylib depending on platform); we only call read-only
    // enumeration functions below and always destroy what we create.
    let entry = match unsafe { ash::Entry::load() } {
        Ok(e) => e,
        Err(e) => return (false, format!("failed to load the Vulkan loader: {e}")),
    };

    let app_info = vk::ApplicationInfo::default()
        .application_name(c"steamcmd-bases-test-exe")
        .api_version(vk::API_VERSION_1_0);
    let create_info = vk::InstanceCreateInfo::default().application_info(&app_info);

    let instance = match unsafe { entry.create_instance(&create_info, None) } {
        Ok(i) => i,
        Err(e) => return (false, format!("failed to create a Vulkan instance: {e:?}")),
    };

    let devices = match unsafe { instance.enumerate_physical_devices() } {
        Ok(d) => d,
        Err(e) => {
            unsafe { instance.destroy_instance(None) };
            return (false, format!("failed to enumerate physical devices: {e:?}"));
        }
    };

    let names: Vec<String> = devices
        .iter()
        .map(|&device| {
            let props = unsafe { instance.get_physical_device_properties(device) };
            props
                .device_name_as_c_str()
                .map(|n| n.to_string_lossy().into_owned())
                .unwrap_or_else(|_| "<unknown>".to_string())
        })
        .collect();

    unsafe { instance.destroy_instance(None) };

    if names.is_empty() {
        (
            false,
            "Vulkan instance created but no physical devices were found".to_string(),
        )
    } else {
        (
            true,
            format!("Found {} Vulkan device(s): {}", names.len(), names.join(", ")),
        )
    }
}
