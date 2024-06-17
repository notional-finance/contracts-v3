// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

/// @dev Specification for flash lenders compatible with ERC-7399
interface IERC7399 {
    /// @dev The amount of currency available to be lent.
    /// @param asset The loan currency.
    /// @return The amount of `asset` that can be borrowed.
    function maxFlashLoan(address asset) external view returns (uint256);

    /// @dev The fee to be charged for a given loan.
    /// @param asset The loan currency.
    /// @param amount The amount of assets lent.
    /// @return The amount of `asset` to be charged for the loan, on top of the returned principal.
    function flashFee(address asset, uint256 amount) external view returns (uint256);

    /// @dev Initiate a flash loan.
    /// @param loanReceiver The address receiving the flash loan
    /// @param asset The asset to be loaned
    /// @param amount The amount to loaned
    /// @param data The ABI encoded user data
    /// @param callback The address and signature of the callback function
    /// @return result ABI encoded result of the callback
    function flash(
        address loanReceiver,
        address asset,
        uint256 amount,
        bytes calldata data,
        function(address, address, address, uint256, uint256, bytes memory) external returns (bytes memory) callback
    )
        external
        returns (bytes memory);
    /// @dev Alternative entry point for the ERC7399 flash loan, without function pointers. Packs data to convert the
    /// legacy flash loan into an ERC7399 flash loan. Then it calls the legacy flash loan. Once the flash loan is done,
    /// checks if there is any return data and returns it.
    function flash(
        address loanReceiver,
        address asset,
        uint256 amount,
        bytes calldata initiatorData,
        address callbackTarget,
        bytes4 callbackSelector
    )
        external
        returns (bytes memory result);
}
