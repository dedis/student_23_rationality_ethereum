// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

/**
 * @title Bribery
 * @dev This contract implements a bribery attack on the Ethereum Proof of Stake (PoS) blockchain.
 * @notice The contract is deployed on the attacking EVM-compatible blockchain. The attacker can use the contract to coordinate an attack on the target blockchain (Ethereum in this case) and distribute the reward among the colluders.
 * @author athenapk
 */
contract Bribery {
    /**
     * @dev Constant representing the maximum integer value.
     */
    uint256 constant MAX_INT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /**
     * @dev Set expiration time for this contract. Arbitrarily set to 42 days after deployment. In practice, it should be long enough to engage enough validators to control a significant percentage of the target blockchain stake.
     */
    uint public expirationTime = block.timestamp + 42 days;

    /**
     * @dev Set the minimum amount each colluder needs to deposit to participate in the attack. This is done to prevent the defection of colluders.
     * For the purpose of this exercise, we set the minimum deposit amount to 0 ETH.
     */
    uint public constant minDepositAmount = 0 ether;

    /**
     * @dev Public variable that stores the total number of colluders in the contract.
     */
    uint public totalColluders = 0;

    /**
     * @notice Private variable to store the reward amount, which will be distributed among the colluders. They should be paid more than they would earn by following the honest protocol and be compensated for the risk that they may be slashed if the attack is detected.
     */
    uint private rewardAmount;

    /**
     * @dev Public variable to store the amount of staked ether. It is set initially to MAX_INT to avoid miscalculations before the variable is updated.
     */
    uint public stakedEther = MAX_INT;

    /**
     * @dev The amount of staked Ether controlled by the colluding validators.
     */
    uint stakedEtherControlled = 0;

    /**
     * @dev The addressToCensor constant represents the Ethereum address that needs to be censored. For the purposes of this exercise, it is set to the address of my MetaMask wallet.
     */
    // TODO: create function only callable by the attacker to set the address to censor, so that it's not visible to everyone from the beginning.
    address constant addressToCensor =
        0x707Ec32887AE799A627c960f97Ad78515B30EAe4;

    bool attackHasBegun = false;

    /**
     * @dev Struct representing a validator in the Ethereum Proof-of-Stake (PoS) blockchain.
     * @param validatorId Unique identifier for the validator.
     * @param effectiveBalance Effective balance of the validator.
     * @param status Status of the validator (e.g. active, inactive, slashed, etc.).
     */
    struct Validator {
        string validatorId;
        uint effectiveBalance;
        string status;
    }

    /**
     * @dev Struct representing a colluder in the bribery attack.
     * @param colluderAddress The address of the colluder in the attacking blockchain.
     * @param validatorId The ID of the Ethereum validator that the colluder controls.
     * @param depositAmount The amount of deposit the colluder has made to participate in the attack.
     * @param hasBeenPaid A boolean indicating whether the colluder has been compensated for their participation in the attack.
     * @param isSlashed A boolean indicating whether the colluder has been slashed.
     */
    struct Colluder {
        address colluderAddress;
        string validatorId;
        uint depositAmount;
        bool hasBeenPaid;
        bool isSlashed;
    }

    /**
     * @dev Mapping of colluder IDs to their respective Colluder struct.
     */
    mapping(uint => Colluder) public colluders;

    /**
     * @dev Mapping of validator IDs to their respective Validator struct.
     */
    mapping(string validatorId => Validator) public validators;

    /**
     * @dev A mapping that associates a validator ID with a colluder ID.
     * The colluder ID is an unsigned integer that represents the ID of the colluder who owns the validator.
     */
    mapping(string validatorId => uint colluderId) public validatorToColluder;

    /**
     * @dev Emitted when a new colluder is added to the list of colluders.
     * @param validatorId The ID of the Ethereum validator associated with the colluder.
     */
    event NewColluder(string validatorId, string signature, bytes32 message);

    /**
     * @dev Emitted when the colluding validators control a sufficient percentage of the stake to successfully execute the attack. This event should be picked up by the colluders, who would then begin to censor the target address from any transactions.
     * @param addressToCensor The address that is being targeted for censorship.
     */
    event BeginAttack(address addressToCensor);

    mapping(address => uint256) public nonces;

    // =========================================
    // ========= Initialisation phase ==========
    // =========================================

    /**
     * @dev The attacker can use this function to deposit the reward amount to the contract. They can deposit money multiple times, increasing the reward if needed. The function is public, allowing for the possibility of crowdfunding the attack.
     */
    function depositReward() public payable {
        rewardAmount += msg.value;
    }

    /**
     * @notice Colluders can use this function to check the reward amount before committing to the attack.
     * @return The reward amount that would be shared among colluders after successfully executing the bribery attack.
     */
    function getRewardAmountInformation() public view returns (uint) {
        return rewardAmount;
    }

    // =========================================
    // ============= Commit phase ==============
    // =========================================

    /**
     * @notice To be called by each colluder to declare their participation in the attack. Reverts if the minimum deposit amount is not met. The function adds the caller to the list of colluding nodes, records the deposit amount and the fact that the node has not received the reward yet.
     * @param _validatorId The ID of the validator associated with the colluder.
     */
    function commit(
        string calldata _validatorId,
        string calldata _signature
    ) public payable {
        if (
            msg.value < minDepositAmount ||
            validatorIsOnValidatorList(_validatorId) ||
            !attackHasBegun
        ) {
            revert();
        }
        totalColluders++;
        colluders[totalColluders] = Colluder(
            msg.sender,
            _validatorId,
            msg.value,
            false,
            false
        );
        validatorToColluder[_validatorId] = totalColluders;
        emit NewColluder(
            _validatorId,
            _signature,
            getMessageHash(msg.sender, _validatorId)
        );
    }

    /**
     * @dev Verify the status of validators and slash colluders whose validators are inactive or have insufficient funds.
     */
    function verifyValidators() public {
        for (uint i = 1; i <= totalColluders; i++) {
            if (
                !_validatorIsActive(colluders[i].validatorId) ||
                !validatorHasSufficientFunds(colluders[i].validatorId)
            ) {
                colluders[i].isSlashed = true;
                validatorToColluder[colluders[i].validatorId] = 0;
            } else {
                // we put this here in case the colluder has been slashed and then becomes active again
                colluders[i].isSlashed = false;
            }
        }
    }

    /**
     * @dev Checks if a validator has sufficient stake to participate in the consensus protocol.
     * @param _validatorId The ID of the validator to check.
     * @return A boolean indicating whether the validator has sufficient funds or not.
     */
    function validatorHasSufficientFunds(
        string memory _validatorId
    ) public view returns (bool) {
        Validator memory v = validators[_validatorId];
        return v.effectiveBalance > 16000000000;
    }

    /**
     * @dev Checks if a validator with the given ID is active and online.
     * @param _validatorId The ID of the validator to check.
     * @return A boolean indicating whether the validator is active and online.
     */
    function _validatorIsActive(
        string memory _validatorId
    ) public view returns (bool) {
        Validator memory v = validators[_validatorId];
        // https://ethereum.stackexchange.com/questions/30912/how-to-compare-strings-in-solidity
        return
            keccak256(abi.encodePacked(v.status)) ==
            keccak256(abi.encodePacked("active_online"));
    }

    /**
     * @dev Returns the hash of the message to be signed by the validator. To avoid replay attacks, the message includes the address of the contract, the chain ID, and a nonce. (https://programtheblockchain.com/posts/2018/02/17/signing-and-verifying-messages-in-ethereum/)
     */
    function getMessageHash(
        address _signer,
        string memory _validatorId
    ) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    address(this),
                    block.chainid,
                    _signer,
                    nonces[_signer],
                    _validatorId
                )
            );
    }

    // =========================================
    // ============= Attack phase ==============
    // =========================================

    /**
     * @dev Checks if the colluders control a sufficient percentage of the stake to successfully execute the attack.
     * @param percentage The percentage of the stake that the colluders need to control.
     * @return A boolean indicating whether the colluders control the required percentage of the stake.
     */
    function percentageOfStakedEtherControlledIs(
        uint percentage
    ) public view returns (bool) {
        percentage = percentage / 100;
        return stakedEtherControlled / stakedEther >= percentage;
    }

    function beginAttackIfPossible() public {
        if (percentageOfStakedEtherControlledIs(66)) {
            emit BeginAttack(addressToCensor);
            attackHasBegun = true;
        }
    }

    // ====================================================
    // ======== Functions to be used by the oracle ========
    // ====================================================

    /**
     * @dev Function that the off-chain oracle script uses to post validator information. Also increments the nonce of the validator to prevent replay attacks.
     * @param _validatorId The ID of the validator.
     * @param _effectiveBalance The effective balance of the validator.
     * @param _status The status of the validator.
     */
    function postValidatorInfo(
        string memory _validatorId,
        uint _effectiveBalance,
        string memory _status
    ) public {
        validators[_validatorId] = Validator(
            _validatorId,
            _effectiveBalance,
            _status
        );
        nonces[colluders[validatorToColluder[_validatorId]].colluderAddress]++;
    }

    function updateStakedEther(uint amount) public {
        stakedEther = amount;
    }

    // ==================================
    // ======== Helper functions ========
    // ==================================
    function stringIsEmpty(string memory _string) public pure returns (bool) {
        return bytes(_string).length == 0;
    }

    function validatorIsOnValidatorList(
        string memory _validatorId
    ) public view returns (bool) {
        return !stringIsEmpty(validators[_validatorId].status);
    }
}
