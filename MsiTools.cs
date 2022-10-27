[DllImport("msi.dll", CharSet = CharSet.Unicode, PreserveSig = true, SetLastError = true, ExactSpelling = true)]
private static extern UInt32 MsiOpenPackageExW(string szPackagePath, uint openOptions, out IntPtr hProduct);
[DllImport("msi.dll", CharSet = CharSet.Unicode, PreserveSig = true, SetLastError = true, ExactSpelling = true)]
private static extern uint MsiCloseHandle(IntPtr hAny);
[DllImport("msi.dll", CharSet = CharSet.Unicode, PreserveSig = true, SetLastError = true, ExactSpelling = true)]
private static extern uint MsiGetPropertyW(IntPtr hAny, string name, StringBuilder buffer, ref int bufferLength);
private static string GetPackageProperty(string msi, string property)
{
    IntPtr MsiHandle = IntPtr.Zero;
    try
    {
        var res = MsiOpenPackageExW(msi, 1, out MsiHandle);
        if (res != 0)
        {
            throw new Exception("Failed to open package " + res.ToString());
        }
        int length = 256;
        var buffer = new StringBuilder(length);
        res = MsiGetPropertyW(MsiHandle, property, buffer, ref length);
        return buffer.ToString();
    }
    finally
    {
        if (MsiHandle != IntPtr.Zero)
        {
            MsiCloseHandle(MsiHandle);
        }
    }
}
public static string GetProductCode(string msi)
{
    return GetPackageProperty(msi, "ProductCode");
}
public static string GetProductName(string msi)
{
    return GetPackageProperty(msi, "ProductName");
}
public static string GetProductVersion(string msi)
{
    return GetPackageProperty(msi, "ProductVersion");
}