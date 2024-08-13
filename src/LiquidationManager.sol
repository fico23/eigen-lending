// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "eigenlayer-contracts/src/contracts/permissions/Pausable.sol";
import "eigenlayer-middleware/src/interfaces/IServiceManager.sol";
import {BLSApkRegistry} from "eigenlayer-middleware/src/BLSApkRegistry.sol";
import {RegistryCoordinator} from "eigenlayer-middleware/src/RegistryCoordinator.sol";
import {BLSSignatureChecker, IRegistryCoordinator} from "eigenlayer-middleware/src/BLSSignatureChecker.sol";
import {OperatorStateRetriever} from "eigenlayer-middleware/src/OperatorStateRetriever.sol";
import "eigenlayer-middleware/src/libraries/BN254.sol";
import {ILending} from "./ILending.sol";

contract LiquidationManager is Pausable, BLSSignatureChecker, OperatorStateRetriever {
    using BN254 for BN254.G1Point;

    address public aggregator;

    /* MODIFIERS */
    modifier onlyAggregator() {
        require(msg.sender == aggregator, "Aggregator must be the caller");
        _;
    }

    constructor(IRegistryCoordinator _registryCoordinator, address _aggregator)
        BLSSignatureChecker(_registryCoordinator)
    {
        aggregator = _aggregator;
    }

    // NOTE: this function responds to existing tasks.
    function liquidate(address user, NonSignerStakesAndSignature memory nonSignerStakesAndSignature)
        external
        onlyAggregator
    {
        // uint32 taskCreatedBlock = task.taskCreatedBlock;
        // bytes calldata quorumNumbers = task.quorumNumbers;
        // uint32 quorumThresholdPercentage = task.quorumThresholdPercentage;

        // // check that the task is valid, hasn't been responsed yet, and is being responsed in time
        // require(
        //     keccak256(abi.encode(task)) ==
        //         allTaskHashes[taskResponse.referenceTaskIndex],
        //     "supplied task does not match the one recorded in the contract"
        // );
        // // some logical checks
        // require(
        //     allTaskResponses[taskResponse.referenceTaskIndex] == bytes32(0),
        //     "Aggregator has already responded to the task"
        // );
        // require(
        //     uint32(block.number) <=
        //         taskCreatedBlock + TASK_RESPONSE_WINDOW_BLOCK,
        //     "Aggregator has responded to the task too late"
        // );

        // /* CHECKING SIGNATURES & WHETHER THRESHOLD IS MET OR NOT */
        // // calculate message which operators signed
        // bytes32 message = keccak256(abi.encode(user));

        // // check the BLS signature
        // (
        //     QuorumStakeTotals memory quorumStakeTotals,
        //     bytes32 hashOfNonSigners
        // ) = checkSignatures(
        //         message,
        //         quorumNumbers,
        //         taskCreatedBlock,
        //         nonSignerStakesAndSignature
        //     );

        // // check that signatories own at least a threshold percentage of each quourm
        // for (uint i = 0; i < quorumNumbers.length; i++) {
        //     // we don't check that the quorumThresholdPercentages are not >100 because a greater value would trivially fail the check, implying
        //     // signed stake > total stake
        //     require(
        //         quorumStakeTotals.signedStakeForQuorum[i] *
        //             _THRESHOLD_DENOMINATOR >=
        //             quorumStakeTotals.totalStakeForQuorum[i] *
        //                 uint8(quorumThresholdPercentage),
        //         "Signatories do not own at least threshold percentage of a quorum"
        //     );
        // }

        // TaskResponseMetadata memory taskResponseMetadata = TaskResponseMetadata(
        //     uint32(block.number),
        //     hashOfNonSigners
        // );
        // // updating the storage with task responsea
        // allTaskResponses[taskResponse.referenceTaskIndex] = keccak256(
        //     abi.encode(taskResponse, taskResponseMetadata)
        // );

        // // emitting event
        // emit TaskResponded(taskResponse, taskResponseMetadata);
    }
}
